#!/usr/bin/env python3
"""Local server (127.0.0.1 only, read-only) that shows the diff of every changed file
of a git repo. Usage: http://127.0.0.1:8765/?t=<token>&d=<repo path>#<file>"""
import hmac
import html
import os
import subprocess
import socketserver
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

PORT = int(os.environ.get("STATUSLINE_PORT", "8765"))
STATE = os.environ.get("STATUSLINE_STATE") or os.path.join(
    os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "claude-code-statusline")
VALID_HOSTS = {f"127.0.0.1:{PORT}", f"localhost:{PORT}"}


def expected_token():
    try:
        with open(os.path.join(STATE, "token")) as f:
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


MAX_DIFF = 512 * 1024   # bytes per file; anything beyond is truncated
GIT_TIMEOUT = 10        # seconds per git call

try:
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "VERSION")) as _f:
        VERSION = _f.read().strip()
except OSError:
    VERSION = "unknown"


def git(repo, *args):
    try:
        r = subprocess.run(["git", "-C", repo, *args], capture_output=True, text=True,
                           errors="replace", timeout=GIT_TIMEOUT)
    except subprocess.TimeoutExpired:
        return ""
    return r.stdout


def file_diff(repo, status, f):
    if status == "??":
        return git(repo, "diff", "--no-index", "--no-color", "--", "/dev/null", os.path.join(repo, f))
    return git(repo, "diff", "HEAD", "--no-color", "--", f)


def render(text):
    out = []
    for ln in text.splitlines():
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


# Status bar legend: (symbol, meaning). Rendered at /help.
HELP = [
    ("Line 1 · model and git", [
        ("Model (effort)", "Active model and, in parentheses, the reasoning effort level."),
        ("⚡", "Fast mode on."),
        ("🤖 name", "You are inside a specific agent."),
        ("project", "Current working folder."),
        ("⎇ branch", "Current git branch."),
        ("↑N", "Local commits you have not pushed yet."),
        ("↓N", "Remote commits you have not pulled yet."),
        ("●N", "Files staged for commit."),
        ("✚N", "Modified files that are not staged."),
        ("?N", "New untracked files."),
        ("✖N", "Files with a merge conflict."),
        ("✔ clean", "No pending changes."),
        ("PR #N", "The branch's pull request. Green = approved, red = changes requested, yellow = pending."),
        ("ⓘ", "This help."),
    ]),
    ("Line 2 · usage", [
        ("ctx ███░░ N%", "How full the conversation context is, with tokens used/total. Green < 50%, yellow < 80%, red from 80%."),
        ("5h ███░░ N% ↻", "Usage of your subscription's 5-hour limit and countdown until it resets."),
        ("7d ███░░ N% ↻", "Usage of the weekly limit and countdown until it resets. Same colors as ctx."),
        ("$N.NN", "Session cost. Green < $1, yellow < $5, red from $5."),
        ("$N/h", "Spend rate per hour (shown after 5 min of session). Grey < $15/h, yellow < $30/h, red from $30/h."),
        ("cache N%", "Share of the prompt that is reused from the cache. High = cheaper. Green ≥ 70%, yellow ≥ 40%, red below."),
        ("↺HH:MM", "Time at which the prompt cache expires (5 min after the last activity). Green while more than 1 min is left, yellow after that; red \"exp\" once expired."),
        ("Cache expired…", "Warning line: with the cache expired and a large context (≥ 50k), the next prompt re-caches all of it. Shows the estimated cost; consider /compact. Price adjustable with STATUSLINE_RECACHE_USD_PER_MTOK."),
        ("↓N ↑N", "Accumulated tokens: ↓ read (input) and ↑ written (output)."),
        ("⏱", "Session duration."),
        ("+N -N", "Lines of code added (green) and deleted (red) in the session."),
    ]),
    ("Line 3 · changed files", [
        ("Δ", "List of every file changed against HEAD. Cmd+click one to see its diff."),
        ("M", "Modified."),
        ("A", "Added (staged)."),
        ("D", "Deleted."),
        ("R", "Renamed."),
        ("U", "Conflict."),
        ("?", "New, untracked."),
    ]),
]


def help_page():
    body = ""
    for title, rows in HELP:
        trs = "".join(f"<tr><td class=k>{html.escape(k)}</td><td>{html.escape(v)}</td></tr>" for k, v in rows)
        body += f"<section><h2>{html.escape(title)}</h2><table>{trs}</table></section>"
    extra = ("table{border-collapse:collapse;width:100%}td{padding:5px 12px;border-top:1px solid var(--bd);vertical-align:top}"
             ".k{white-space:nowrap;font-weight:600;width:1%}")
    return ("<!doctype html><meta charset=utf-8><title>Help · status bar</title>"
            f"<style>{CSS}{extra}section{{scroll-margin-top:0}}</style>"
            "<p style='margin:16px'>What each part of the Claude Code status bar means.</p>" + body +
            f"<p style='margin:16px' class=m>claude-code-statusline v{html.escape(VERSION)}</p>")


def diff_page(repo):
    files = []
    for ln in git(repo, "status", "--porcelain", "-uall").splitlines():
        status, f = ln[:2], ln[3:].split(" -> ")[-1].strip('"')
        files.append((status, f))
    files.sort(key=lambda x: x[1])
    nav = "".join(f'<a href="#{html.escape(f, quote=True)}">{html.escape(f)}</a>' for _, f in files)
    body = ""
    for status, f in files:
        d = file_diff(repo, status, f)
        if len(d) > MAX_DIFF:
            d = d[:MAX_DIFF] + f"\n... diff truncated (more than {MAX_DIFF // 1024} KiB)\n"
        body += (f'<section id="{html.escape(f, quote=True)}"><h2>{html.escape(status.strip() or "M")} '
                 f'{html.escape(f)}</h2><pre>{render(d) if d.strip() else "<span class=l>(no text changes)</span>"}</pre></section>')
    if not files:
        body = "<p style='margin:16px'>No changes against HEAD.</p>"
    title = f"Changes · {os.path.basename(repo)} ({len(files)})"
    return (f"<!doctype html><meta charset=utf-8><title>{html.escape(title)}</title>"
            f"<style>{CSS}</style><nav>{nav}</nav>{body}")


class Server(ThreadingHTTPServer):
    def server_bind(self):
        # HTTPServer.server_bind does a reverse DNS lookup (socket.getfqdn) that can take many
        # seconds in some environments (e.g. macOS on CI) and delays startup. We do not use it.
        socketserver.TCPServer.server_bind(self)
        self.server_name = self.server_address[0]
        self.server_port = self.server_address[1]


class H(BaseHTTPRequestHandler):
    def deny(self, code, msg):
        self.send_response(code)
        self.end_headers()
        self.wfile.write(msg)

    def do_GET(self):
        # Anti DNS-rebinding: only requests addressed to our host:port are served
        if self.headers.get("Host", "").lower() not in VALID_HOSTS:
            self.deny(403, b"host not allowed")
            return
        q = parse_qs(urlparse(self.path).query)
        # Secret token: without it no website can read your diffs even if it guesses the port
        expected = expected_token()
        given = (q.get("t") or [""])[0]
        if not expected or not hmac.compare_digest(given.encode(), expected.encode()):
            self.deny(403, b"invalid token")
            return
        if urlparse(self.path).path == "/help":
            self.respond(help_page())
            return
        repo = (q.get("d") or [""])[0]
        top = git(repo, "rev-parse", "--show-toplevel").strip() if os.path.isdir(repo) else ""
        if not top:
            self.deny(400, b"d= must be a git repo")
            return
        self.respond(diff_page(top))

    def respond(self, text):
        body = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        self.send_header("Content-Security-Policy", "default-src 'none'; style-src 'unsafe-inline'")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    # The pid lets statusline.sh restart the server when the code changes
    try:
        with open(os.path.join(STATE, "server.pid"), "w") as f:
            f.write(str(os.getpid()))
    except OSError:
        pass
    Server(("127.0.0.1", PORT), H).serve_forever()
