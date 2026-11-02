#!/usr/bin/env python3
"""Servidor local (solo 127.0.0.1, solo lectura) que muestra el diff de todos los ficheros
cambiados de un repo git. Uso: http://127.0.0.1:8765/?t=<token>&d=<ruta repo>#<fichero>"""
import hmac
import html
import os
import subprocess
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PUERTO = int(os.environ.get("STATUSLINE_PORT", "8765"))
ESTADO = os.environ.get("STATUSLINE_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "claude-code-statusline")
HOSTS_VALIDOS = {f"127.0.0.1:{PUERTO}", f"localhost:{PUERTO}"}


def token_esperado():
    try:
        with open(os.path.join(ESTADO, "token")) as f:
            return f.read().strip()
    except OSError:
        return ""

CSS = """
:root{color-scheme:light dark;--bg:#fff;--fg:#1f2328;--bar:#f6f8fa;--bd:#d0d7de;--add:#dafbe1;--del:#ffebe9;--hunk:#ddf4ff;--mut:#656d76}
@media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--bar:#161b22;--bd:#30363d;--add:#12361f;--del:#3d1d20;--hunk:#10243d;--mut:#8b949e}}
body{margin:0;background:var(--bg);color:var(--fg);font:13px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace}
nav{position:sticky;top:0;background:var(--bar);border-bottom:1px solid var(--bd);padding:8px 16px;z-index:2;max-height:30vh;overflow:auto}
nav a{margin-right:14px;color:inherit;white-space:nowrap}
section{margin:16px;border:1px solid var(--bd);border-radius:6px;scroll-margin-top:calc(30vh + 8px)}
section:target{outline:2px solid #388bfd}
h2{margin:0;padding:6px 12px;background:var(--bar);border-bottom:1px solid var(--bd);font-size:13px;position:sticky;top:0}
pre{margin:0;overflow-x:auto}
.l{display:block;padding:0 12px;white-space:pre}
.a{background:var(--add)}.d{background:var(--del)}.h{background:var(--hunk);color:var(--mut)}.m{color:var(--mut)}
"""


def git(repo, *args):
    r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True, errors="replace")
    return r.stdout


def diff_fichero(repo, estado, f):
    if estado == "??":
        return git(repo, "diff", "--no-index", "--no-color", "--", "/dev/null", os.path.join(repo, f))
    return git(repo, "diff", "HEAD", "--no-color", "--", f)


def pinta(texto):
    out = []
    for ln in texto.splitlines():
        c = "m"
        if ln.startswith("@@"):
            c = "h"
        elif ln.startswith("+") and not ln.startswith("+++"):
            c = "a"
        elif ln.startswith("-") and not ln.startswith("---"):
            c = "d"
        elif not ln.startswith((" ", "diff", "index", "+++", "---", "new file", "deleted")):
            c = ""
        out.append(f'<span class="l {c}">{html.escape(ln) or " "}</span>')
    return "".join(out)


# Leyenda de la barra de estado: (símbolo, significado). Se pinta en /ayuda.
AYUDA = [
    ("Línea 1 · modelo y git", [
        ("Modelo (esfuerzo)", "Modelo activo y, entre paréntesis, el nivel de esfuerzo de razonamiento."),
        ("⚡", "Modo rápido activado."),
        ("🤖 nombre", "Estás dentro de un agente concreto."),
        ("proyecto", "Carpeta de trabajo actual."),
        ("⎇ rama", "Rama de git actual."),
        ("↑N", "Commits locales que aún no has subido (push)."),
        ("↓N", "Commits en remoto que aún no has bajado (pull)."),
        ("●N", "Ficheros preparados para commit (staged)."),
        ("✚N", "Ficheros modificados sin preparar."),
        ("?N", "Ficheros nuevos sin seguimiento."),
        ("✖N", "Ficheros con conflicto de merge."),
        ("✔ limpio", "No hay ningún cambio pendiente."),
        ("PR #N", "Pull request de la rama. Verde = aprobada, rojo = piden cambios, amarillo = pendiente."),
        ("ⓘ", "Esta ayuda."),
    ]),
    ("Línea 2 · consumo", [
        ("ctx ███░░ N%", "Cuánto del contexto de la conversación está lleno, con tokens usados/totales. Verde < 50 %, amarillo < 80 %, rojo a partir de 80 %."),
        ("5h ███░░ N% ↻", "Uso del límite de 5 horas de tu suscripción y cuenta atrás hasta que se renueva."),
        ("7d ███░░ N% ↻", "Uso del límite semanal y cuenta atrás hasta que se renueva. Mismos colores que ctx."),
        ("$N.NN", "Coste de la sesión. Verde < 1 $, amarillo < 5 $, rojo a partir de 5 $."),
        ("caché N%", "Parte del prompt que se reutiliza de la caché. Alto = más barato. Verde ≥ 70 %, amarillo ≥ 40 %, rojo por debajo."),
        ("↓N ↑N", "Tokens acumulados: ↓ leídos (entrada) y ↑ escritos (salida)."),
        ("⏱", "Duración de la sesión."),
        ("+N -N", "Líneas de código añadidas (verde) y borradas (rojo) en la sesión."),
    ]),
    ("Línea 3 · ficheros cambiados", [
        ("Δ", "Lista de todos los ficheros cambiados respecto a HEAD. Haz Cmd+clic en uno para ver su diff."),
        ("M", "Modificado."),
        ("A", "Añadido (staged)."),
        ("D", "Borrado."),
        ("R", "Renombrado."),
        ("U", "Conflicto."),
        ("?", "Nuevo, sin seguimiento."),
    ]),
]


def pagina_ayuda():
    cuerpo = ""
    for titulo, filas in AYUDA:
        trs = "".join(f"<tr><td class=k>{html.escape(k)}</td><td>{html.escape(v)}</td></tr>" for k, v in filas)
        cuerpo += f"<section><h2>{html.escape(titulo)}</h2><table>{trs}</table></section>"
    extra = ("table{border-collapse:collapse;width:100%}td{padding:5px 12px;border-top:1px solid var(--bd);vertical-align:top}"
             ".k{white-space:nowrap;font-weight:600;width:1%}")
    return ("<!doctype html><meta charset=utf-8><title>Ayuda · barra de estado</title>"
            f"<style>{CSS}{extra}section{{scroll-margin-top:0}}</style>"
            "<p style='margin:16px'>Qué significa cada cosa de la barra de estado de Claude Code.</p>" + cuerpo)


def pagina(repo):
    ficheros = []
    for ln in git(repo, "status", "--porcelain", "-uall").splitlines():
        est, f = ln[:2], ln[3:].split(" -> ")[-1].strip('"')
        ficheros.append((est, f))
    ficheros.sort(key=lambda x: x[1])
    nav = "".join(f'<a href="#{html.escape(f, quote=True)}">{html.escape(f)}</a>' for _, f in ficheros)
    cuerpo = ""
    for est, f in ficheros:
        d = diff_fichero(repo, est, f)
        cuerpo += (f'<section id="{html.escape(f, quote=True)}"><h2>{html.escape(est.strip() or "M")} '
                   f'{html.escape(f)}</h2><pre>{pinta(d) if d.strip() else "<span class=l>(sin cambios de texto)</span>"}</pre></section>')
    if not ficheros:
        cuerpo = "<p style='margin:16px'>Sin cambios respecto a HEAD.</p>"
    titulo = f"Cambios · {os.path.basename(repo)} ({len(ficheros)})"
    return (f"<!doctype html><meta charset=utf-8><title>{html.escape(titulo)}</title>"
            f"<style>{CSS}</style><nav>{nav}</nav>{cuerpo}")


class H(BaseHTTPRequestHandler):
    def deniega(self, codigo, msg):
        self.send_response(codigo)
        self.end_headers()
        self.wfile.write(msg)

    def do_GET(self):
        # Anti DNS-rebinding: solo se atienden peticiones dirigidas a nuestro host:puerto
        if self.headers.get("Host", "").lower() not in HOSTS_VALIDOS:
            self.deniega(403, b"host no permitido")
            return
        q = parse_qs(urlparse(self.path).query)
        # Token secreto: sin él ninguna web puede leer tus diffs aunque adivine el puerto
        esperado = token_esperado()
        dado = (q.get("t") or [""])[0]
        if not esperado or not hmac.compare_digest(dado.encode(), esperado.encode()):
            self.deniega(403, b"token invalido")
            return
        if urlparse(self.path).path == "/ayuda":
            self.responde(pagina_ayuda())
            return
        repo = (q.get("d") or [""])[0]
        top = git(repo, "rev-parse", "--show-toplevel").strip() if os.path.isdir(repo) else ""
        if not top:
            self.deniega(400, b"d= debe ser un repo git")
            return
        self.responde(pagina(top))

    def responde(self, texto):
        cuerpo = texto.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
        self.end_headers()
        self.wfile.write(cuerpo)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", PUERTO), H).serve_forever()
