#!/usr/bin/env python3
"""Local server (127.0.0.1 only, read-only) that shows the diff of every changed file
of a git repo. Usage: http://127.0.0.1:8765/?t=<token>&d=<repo path>#<file>"""
import hmac
import html
import json
import os
import re
import secrets
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
:root{color-scheme:light dark;--bg:#fff;--fg:#1f2328;--bar:#f6f8fa;--bd:#d0d7de;--add:#dafbe1;--del:#ffebe9;--hunk:#ddf4ff;--mut:#656d76;--addfg:#1a7f37;--delfg:#cf222e}
@media(prefers-color-scheme:dark){:root{--bg:#0d1117;--fg:#e6edf3;--bar:#161b22;--bd:#30363d;--add:#12361f;--del:#3d1d20;--hunk:#10243d;--mut:#8b949e;--addfg:#3fb950;--delfg:#f85149}}
body{margin:0;background:var(--bg);color:var(--fg);font:13px/1.45 ui-monospace,SFMono-Regular,Menlo,monospace}
nav{position:sticky;top:0;background:var(--bar);border-bottom:1px solid var(--bd);padding:8px 16px;z-index:2;max-height:30vh;overflow:auto}
nav a{margin-right:14px;color:inherit;white-space:nowrap}
section{margin:16px;border:1px solid var(--bd);border-radius:6px;scroll-margin-top:calc(30vh + 8px)}
section:target{outline:2px solid #388bfd}
h2{margin:0;padding:6px 12px;background:var(--bar);border-bottom:1px solid var(--bd);font-size:13px;position:sticky;top:0}
pre{margin:0;overflow-x:auto}
.l{display:block;padding:0 12px;white-space:pre}
.bar{display:flex;gap:8px;align-items:center;margin-bottom:6px}
.bar button,.bar input{font:inherit;color:inherit;background:var(--bg);border:1px solid var(--bd);border-radius:6px;padding:3px 10px}
.bar button{cursor:pointer}.bar input{min-width:14em}
details.f{margin:16px;border:1px solid var(--bd);border-radius:6px;scroll-margin-top:calc(30vh + 8px)}
details.f:target{outline:2px solid #388bfd}
summary{cursor:pointer;padding:6px 12px;background:var(--bar);font-size:13px}
details[open]>summary{border-bottom:1px solid var(--bd)}
.cnt{margin-left:10px;color:var(--mut)}.cnt .p{color:var(--addfg)}.cnt .n{color:var(--delfg)}
.a{background:var(--add)}.d{background:var(--del)}.h{background:var(--hunk);color:var(--mut)}.m{color:var(--mut)}
"""


MAX_DIFF = 512 * 1024   # bytes per file; anything beyond is truncated
AUTO_COLLAPSE_FILES = 20  # with more changed files than this, the diff page starts with every file folded
GIT_TIMEOUT = 10        # seconds per git call

try:
    with open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "VERSION")) as _f:
        VERSION = _f.read().strip()
except OSError:
    VERSION = "unknown"


def registered_repo(requested):
    """The registry entry equal to `requested` ("" if there is none). statusline.sh adds the top
    level of every repository it runs in to the `repos` file of the state folder, one per line."""
    try:
        with open(os.path.join(STATE, "repos"), encoding="utf-8") as f:
            known = f.read().splitlines()
    except OSError:
        return ""
    for entry in known:
        if entry and entry == requested:
            return entry
    return ""


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


def count_lines(text):
    """(added, removed) lines of a unified diff."""
    plus = sum(1 for ln in text.splitlines() if ln.startswith("+") and not ln.startswith("+++"))
    minus = sum(1 for ln in text.splitlines() if ln.startswith("-") and not ln.startswith("---"))
    return plus, minus


# The only script of the diff page; it is allowed by a per-response nonce and holds no repository data:
# it only reads and toggles the <details> elements that the server rendered.
PAGE_JS = """
(function () {
  var files = [].slice.call(document.querySelectorAll('details.f'));
  var links = [].slice.call(document.querySelectorAll('nav a'));
  var key = 'statusline:folded:' + (document.body.getAttribute('data-repo') || '');
  var saved = {};
  try { saved = JSON.parse(localStorage.getItem(key) || '{}') || {}; } catch (e) {}
  function save() {
    var state = {};
    files.forEach(function (f) { state[f.id] = f.open; });
    try { localStorage.setItem(key, JSON.stringify(state)); } catch (e) {}
  }
  files.forEach(function (f) {
    if (Object.prototype.hasOwnProperty.call(saved, f.id)) { f.open = !!saved[f.id]; }
    f.addEventListener('toggle', save);
  });
  function setAll(open) { files.forEach(function (f) { f.open = open; }); }
  function openHash() {
    var id = decodeURIComponent(location.hash.slice(1));
    if (!id) { return; }
    files.forEach(function (f) { if (f.id === id) { f.open = true; f.scrollIntoView(); } });
  }
  document.getElementById('collapse-all').addEventListener('click', function () { setAll(false); });
  document.getElementById('expand-all').addEventListener('click', function () { setAll(true); });
  document.getElementById('filter').addEventListener('input', function (e) {
    var q = e.target.value.toLowerCase();
    files.forEach(function (f) { f.hidden = f.id.toLowerCase().indexOf(q) === -1; });
    links.forEach(function (a) { a.hidden = a.textContent.toLowerCase().indexOf(q) === -1; });
  });
  window.addEventListener('hashchange', openHash);
  openHash();
})();
"""


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


LANG_DIR = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lang")


def _read_lang(code):
    try:
        with open(os.path.join(LANG_DIR, f"{code}.json"), encoding="utf-8") as f:
            return json.load(f)
    except (OSError, ValueError):
        return None


def current_lang():
    """Language code: STATUSLINE_LANG, then the `lang` file of the state folder, then English.
    Anything that is not the code of an existing language file falls back to English."""
    code = os.environ.get("STATUSLINE_LANG", "")
    if not code:
        try:
            with open(os.path.join(STATE, "lang")) as f:
                code = f.read()
        except OSError:
            code = ""
    code = code.strip().lower()[:2]
    if re.fullmatch(r"[a-z]{2}", code) and os.path.isfile(os.path.join(LANG_DIR, f"{code}.json")):
        return code
    return "en"


# Used only if lang/en.json is missing or broken, so the server still answers
_FALLBACK = {"bar": {}, "sections": [],
             "page": {"title": "Help", "intro": "Language files are missing."},
             "diff": {"title": "Changes · {repo} ({count})", "none": "No changes against HEAD.",
                      "no_text": "(no text changes)", "truncated": "... diff truncated (more than {kib} KiB)",
                      "collapse_all": "Collapse all", "expand_all": "Expand all", "filter": "Filter files…"}}


def strings():
    """Texts in the current language. English is the base: a missing key or a legend whose shape
    differs from the English one (tests prevent that) is taken from English."""
    base = _read_lang("en") or _FALLBACK
    code = current_lang()
    lang = _read_lang(code) if code != "en" else None
    if not lang:
        return base
    out = {g: {**base.get(g, {}), **lang.get(g, {})} for g in ("bar", "page", "diff")}
    same_shape = [len(x["rows"]) for x in lang.get("sections", [])] == [len(x["rows"]) for x in base["sections"]]
    out["sections"] = lang["sections"] if same_shape else base["sections"]
    return out


def help_page():
    t = strings()
    body = ""
    for section in t["sections"]:
        # every row has a stable id (the same in all languages) so that the bar can link straight to it
        trs = "".join(f'<tr id="{html.escape(r[2], quote=True)}"><td class=k>{html.escape(r[0])}</td><td>{html.escape(r[1])}</td></tr>'
                      for r in section["rows"])
        body += f"<section><h2>{html.escape(section['title'])}</h2><table>{trs}</table></section>"
    extra = ("table{border-collapse:collapse;width:100%}td{padding:5px 12px;border-top:1px solid var(--bd);vertical-align:top}"
             ".k{white-space:nowrap;font-weight:600;width:1%}tr{scroll-margin-top:16px}"
             "tr:target td{background:var(--hunk);outline:2px solid #388bfd;outline-offset:-2px}")
    return (f"<!doctype html><meta charset=utf-8><title>{html.escape(t['page']['title'])}</title>"
            f"<style>{CSS}{extra}section{{scroll-margin-top:0}}</style>"
            f"<p style='margin:16px'>{html.escape(t['page']['intro'])}</p>" + body +
            f"<p style='margin:16px' class=m>claude-code-statusline v{html.escape(VERSION)}</p>")


def diff_page(repo, nonce):
    files = []
    for ln in git(repo, "status", "--porcelain", "-uall").splitlines():
        status, f = ln[:2], ln[3:].split(" -> ")[-1].strip('"')
        files.append((status, f))
    files.sort(key=lambda x: x[1])
    t = strings()["diff"]
    folded = len(files) > AUTO_COLLAPSE_FILES
    nav = "".join(f'<a href="#{html.escape(f, quote=True)}">{html.escape(f)}</a>' for _, f in files)
    body = ""
    for status, f in files:
        d = file_diff(repo, status, f)
        plus, minus = count_lines(d)
        if len(d) > MAX_DIFF:
            d = d[:MAX_DIFF] + "\n" + t["truncated"].format(kib=MAX_DIFF // 1024) + "\n"
        counts = (f'<span class=cnt><span class=p>+{plus}</span> <span class=n>\u2212{minus}</span></span>'
                  if plus or minus else "")
        body += (f'<details {"" if folded else "open "}class=f id="{html.escape(f, quote=True)}">'
                 f'<summary>{html.escape(status.strip() or "M")} {html.escape(f)}{counts}</summary>'
                 f'<pre>{render(d) if d.strip() else "<span class=l>" + html.escape(t["no_text"]) + "</span>"}</pre></details>')
    if not files:
        body = f"<p style='margin:16px'>{html.escape(t['none'])}</p>"
    title = t["title"].format(repo=os.path.basename(repo), count=len(files))
    toolbar = (f'<div class=bar><button type=button id=collapse-all>{html.escape(t["collapse_all"])}</button>'
               f'<button type=button id=expand-all>{html.escape(t["expand_all"])}</button>'
               f'<input type=search id=filter placeholder="{html.escape(t["filter"], quote=True)}"></div>')
    return (f"<!doctype html><meta charset=utf-8><title>{html.escape(title)}</title>"
            f"<style>{CSS}</style><body data-repo=\"{html.escape(repo, quote=True)}\"><nav>{toolbar}{nav}</nav>{body}"
            f'<script nonce="{nonce}">{PAGE_JS}</script>')


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
        # Only repositories the status bar has registered are served, so a leaked link cannot be
        # used to read the changes of any other repository on the disk. `repo` is the entry of the
        # registry that equals the request, never the request itself.
        repo = registered_repo((q.get("d") or [""])[0])
        top = git(repo, "rev-parse", "--show-toplevel").strip() if repo and os.path.isdir(repo) else ""
        if not top:
            self.deny(400, b"d= must be a repository the status bar knows: open the link from the bar")
            return
        nonce = secrets.token_urlsafe(16)
        self.respond(diff_page(top, nonce), nonce)

    def respond(self, text, nonce=None):
        body = text.encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Cache-Control", "no-store")
        self.send_header("X-Content-Type-Options", "nosniff")
        self.send_header("Referrer-Policy", "no-referrer")
        # No script at all, except the diff page's own one, which is allowed by its per-response nonce
        csp = "default-src 'none'; style-src 'unsafe-inline'" + (f"; script-src 'nonce-{nonce}'" if nonce else "")
        self.send_header("Content-Security-Policy", csp)
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
