"""Security and behaviour tests for diffserver.py (standard library only)."""
import http.client
import re
from html.parser import HTMLParser
import importlib
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN = "t0k3n-for-tests"


def script_text(body):
    """Text of the <script> elements of an HTML page, read with a real HTML parser."""
    chunks = []

    class P(HTMLParser):
        inside = False

        def handle_starttag(self, tag, attrs):
            self.inside = self.inside or tag.lower() == "script"

        def handle_endtag(self, tag):
            if tag.lower() == "script":
                self.inside = False

        def handle_data(self, data):
            if self.inside:
                chunks.append(data)

    P().feed(body)
    return "".join(chunks)


def free_port():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ServerBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.port = free_port()
        os.makedirs(os.path.join(cls.tmp.name, "state"))
        with open(os.path.join(cls.tmp.name, "state", "token"), "w") as f:
            f.write(TOKEN)
        os.environ["STATUSLINE_PORT"] = str(cls.port)
        os.environ["STATUSLINE_STATE"] = os.path.join(cls.tmp.name, "state")
        sys.path.insert(0, ROOT)
        sys.modules.pop("diffserver", None)
        cls.mod = importlib.import_module("diffserver")
        cls.srv = cls.mod.Server(("127.0.0.1", cls.port), cls.mod.H)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

        # Test git repo with "tricky" files
        cls.repo = os.path.join(cls.tmp.name, "repo")
        os.makedirs(cls.repo)
        run = lambda *a: subprocess.run(["git", "-C", cls.repo, *a], check=True, capture_output=True)
        run("init", "-q")
        run("config", "user.email", "t@example.com")
        run("config", "user.name", "t")
        with open(os.path.join(cls.repo, "a.txt"), "w") as f:
            f.write("one\n")
        run("add", "-A")
        run("commit", "-q", "-m", "initial")
        with open(os.path.join(cls.repo, "a.txt"), "w") as f:
            f.write("two\n")
        cls.xss_name = "<img src=x onerror=alert(1)>.txt"
        with open(os.path.join(cls.repo, cls.xss_name), "w") as f:
            f.write("<script>alert(1)</script>\n")
        cls.register(cls.repo)

    @classmethod
    def register(cls, path):
        """What statusline.sh does: add the repository to the registry the server reads."""
        with open(os.path.join(cls.tmp.name, "state", "repos"), "a") as f:
            f.write(path + "\n")

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        cls.tmp.cleanup()

    def get(self, path, host=None):
        c = http.client.HTTPConnection("127.0.0.1", self.port, timeout=15)
        c.putrequest("GET", path, skip_host=True)
        c.putheader("Host", f"127.0.0.1:{self.port}" if host is None else host)
        c.endheaders()
        r = c.getresponse()
        body = r.read().decode(errors="replace")
        c.close()
        return r, body


class Startup(ServerBase):
    def test_startup_does_no_reverse_dns(self):
        # If getfqdn were called again, startup would block in environments with slow DNS
        saved = socket.getfqdn
        socket.getfqdn = lambda *a, **k: self.fail("the server must not call socket.getfqdn")
        try:
            srv = self.mod.Server(("127.0.0.1", 0), self.mod.H)
            srv.server_close()
        finally:
            socket.getfqdn = saved


class Authentication(ServerBase):
    def test_no_token_403(self):
        self.assertEqual(self.get("/help")[0].status, 403)

    def test_wrong_token_403(self):
        self.assertEqual(self.get("/help?t=otro")[0].status, 403)

    def test_empty_token_403(self):
        self.assertEqual(self.get("/help?t=")[0].status, 403)

    def test_right_token_200(self):
        self.assertEqual(self.get(f"/help?t={TOKEN}")[0].status, 200)

    def test_diff_without_token_leaks_nothing(self):
        r, body = self.get(f"/?d={self.repo}")
        self.assertEqual(r.status, 403)
        self.assertNotIn("two", body)

    def test_missing_token_file_always_403(self):
        os.rename(os.path.join(self.tmp.name, "state", "token"), os.path.join(self.tmp.name, "state", "token.bak"))
        try:
            self.assertEqual(self.get("/help?t=")[0].status, 403)
        finally:
            os.rename(os.path.join(self.tmp.name, "state", "token.bak"), os.path.join(self.tmp.name, "state", "token"))


class AntiRebinding(ServerBase):
    def test_foreign_host_403_even_with_valid_token(self):
        for host in ("evil.com", f"evil.com:{self.port}", f"127.0.0.1.evil.com:{self.port}", "", "127.0.0.1:1"):
            with self.subTest(host=host):
                self.assertEqual(self.get(f"/help?t={TOKEN}", host=host)[0].status, 403)

    def test_localhost_allowed(self):
        self.assertEqual(self.get(f"/help?t={TOKEN}", host=f"localhost:{self.port}")[0].status, 200)


class Content(ServerBase):
    def test_security_headers(self):
        r, _ = self.get(f"/help?t={TOKEN}")
        self.assertIn("default-src 'none'", r.getheader("Content-Security-Policy"))
        self.assertEqual(r.getheader("X-Content-Type-Options"), "nosniff")
        self.assertEqual(r.getheader("Referrer-Policy"), "no-referrer")
        self.assertEqual(r.getheader("Cache-Control"), "no-store")

    def test_help_shows_version(self):
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertIn(self.mod.VERSION, body)

    def test_help_documents_what_the_bar_shows(self):
        _, body = self.get(f"/help?t={TOKEN}")
        for item in ("↺HH:MM", "exp HH:MM", "$N/h", "Cache expired", "STATUSLINE_RECACHE_USD_PER_MTOK",
                     "STATUSLINE_PORT", "STATUSLINE_BURN_WARN", "STATUSLINE_BURN_HIGH", "✔ clean", "ⓘ help", "--doctor"):
            with self.subTest(item=item):
                self.assertIn(item, body)

    def test_directory_that_is_not_a_repo_400(self):
        self.assertEqual(self.get(f"/?t={TOKEN}&d={self.tmp.name}")[0].status, 400)

    def test_missing_directory_400(self):
        self.assertEqual(self.get(f"/?t={TOKEN}&d=/no/such/dir")[0].status, 400)

    def test_repo_diff_ok(self):
        r, body = self.get(f"/?t={TOKEN}&d={self.repo}")
        self.assertEqual(r.status, 200)
        self.assertIn("two", body)

    def test_file_names_are_escaped(self):
        _, body = self.get(f"/?t={TOKEN}&d={self.repo}")
        self.assertNotIn("<img src=x", body)
        self.assertNotIn("<script>alert", body)
        self.assertIn("&lt;img src=x", body)

    def test_huge_diff_is_truncated(self):
        big = os.path.join(self.repo, "big.txt")
        with open(big, "w") as f:
            f.write("x" * (self.mod.MAX_DIFF + 4096) + "\n")
        try:
            r, body = self.get(f"/?t={TOKEN}&d={self.repo}")
            self.assertEqual(r.status, 200)
            self.assertIn("diff truncated", body)
        finally:
            os.remove(big)


class Languages(ServerBase):
    def set_lang(self, code):
        path = os.path.join(self.tmp.name, "state", "lang")
        if code is None:
            if os.path.exists(path):
                os.remove(path)
        else:
            with open(path, "w") as f:
                f.write(code)

    def tearDown(self):
        self.set_lang(None)
        os.environ.pop("STATUSLINE_LANG", None)

    def test_default_is_english(self):
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertIn("What each part of the Claude Code status bar means.", body)

    def test_language_file_is_used_without_restart(self):
        self.set_lang("es")
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertIn("Qué significa cada parte de la barra de estado de Claude Code.", body)
        self.set_lang("fr")
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertNotIn("Qué significa", body)
        self.assertIn("barre d", body)

    def test_environment_wins_over_the_file(self):
        self.set_lang("es")
        os.environ["STATUSLINE_LANG"] = "de"
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertIn("Hilfe", body)

    def test_unknown_language_falls_back_to_english(self):
        for code in ("zz", "../etc/passwd", "e/", "1a", ""):
            with self.subTest(code=code):
                self.set_lang(code)
                _, body = self.get(f"/help?t={TOKEN}")
                self.assertIn("What each part of the Claude Code status bar means.", body)

    def test_region_suffix_is_accepted(self):
        self.set_lang("es_ES")
        _, body = self.get(f"/help?t={TOKEN}")
        self.assertIn("Qué significa cada parte", body)

    def test_diff_page_is_translated_too(self):
        self.set_lang("es")
        _, body = self.get(f"/?t={TOKEN}&d={self.repo}")
        self.assertIn("Cambios · repo", body)

    def test_security_behaviour_is_the_same_in_every_language(self):
        self.set_lang("de")
        self.assertEqual(self.get("/help")[0].status, 403)
        self.assertEqual(self.get(f"/help?t={TOKEN}", host="evil.com")[0].status, 403)


class CollapsibleDiffPage(ServerBase):
    def page(self, lang=None):
        if lang:
            with open(os.path.join(self.tmp.name, "state", "lang"), "w") as f:
                f.write(lang)
        try:
            return self.get(f"/?t={TOKEN}&d={self.repo}")
        finally:
            try:
                os.remove(os.path.join(self.tmp.name, "state", "lang"))
            except OSError:
                pass

    def test_each_file_is_a_details_element_open_by_default(self):
        _, body = self.page()
        self.assertEqual(body.count("<details"), 2)
        self.assertEqual(body.count("<details open"), 2)

    def test_summary_shows_status_name_and_line_counts(self):
        _, body = self.page()
        self.assertRegex(body, r"<summary>.*a\.txt.*\+1.*(−|-)1")

    def test_many_files_start_collapsed(self):
        extra = []
        try:
            for i in range(self.mod.AUTO_COLLAPSE_FILES + 1):
                path = os.path.join(self.repo, f"many{i:02}.txt")
                with open(path, "w") as f:
                    f.write("x\n")
                extra.append(path)
            _, body = self.page()
            self.assertGreater(body.count("<details"), self.mod.AUTO_COLLAPSE_FILES)
            self.assertEqual(body.count("<details open"), 0)
        finally:
            for path in extra:
                os.remove(path)

    def test_toolbar_has_collapse_expand_and_filter_in_english(self):
        _, body = self.page()
        for text in ("Collapse all", "Expand all", "Filter files"):
            with self.subTest(text=text):
                self.assertIn(text, body)

    def test_toolbar_is_translated(self):
        _, body = self.page("es")
        self.assertIn("Plegar todo", body)
        self.assertIn("Desplegar todo", body)

    def test_script_is_allowed_only_by_a_per_response_nonce(self):
        r1, body1 = self.page()
        r2, body2 = self.page()
        csp = r1.getheader("Content-Security-Policy")
        self.assertIn("default-src 'none'", csp)
        self.assertNotIn("script-src 'unsafe-inline'", csp)
        self.assertNotIn("unsafe-eval", csp)
        nonce1 = re.search(r"script-src 'nonce-([^']+)'", csp).group(1)
        nonce2 = re.search(r"script-src 'nonce-([^']+)'", r2.getheader("Content-Security-Policy")).group(1)
        self.assertNotEqual(nonce1, nonce2)
        self.assertIn(f'<script nonce="{nonce1}">', body1)
        self.assertGreaterEqual(len(nonce1), 16)

    def test_the_script_contains_no_repository_data(self):
        _, body = self.page()
        script = script_text(body)
        self.assertIn("addEventListener", script)   # we really are looking at the page's script
        for secret in ("a.txt", TOKEN, self.repo, "alert(1)"):
            with self.subTest(secret=secret):
                self.assertNotIn(secret, script)

    def test_only_one_script_and_no_inline_handlers(self):
        scripts, handlers = [], []

        class P(HTMLParser):
            def handle_starttag(self, tag, attrs):
                if tag == "script":
                    scripts.append(attrs)
                handlers.extend((tag, n) for n, _ in attrs if n.lower().startswith("on"))

        _, body = self.page()
        P().feed(body)
        self.assertEqual(len(scripts), 1)
        self.assertEqual(handlers, [], "no element may carry an event-handler attribute")

    def test_help_page_still_has_no_script_at_all(self):
        r, body = self.get(f"/help?t={TOKEN}")
        self.assertNotIn("<script", body)
        self.assertNotIn("script-src", r.getheader("Content-Security-Policy"))


class RegisteredRepositories(ServerBase):
    def make_repo(self, name):
        path = os.path.join(self.tmp.name, name)
        os.makedirs(path)
        subprocess.run(["git", "-C", path, "init", "-q"], check=True, capture_output=True)
        with open(os.path.join(path, "x.txt"), "w") as f:
            f.write("secret-of-" + name + "\n")
        return path

    def test_a_repository_that_was_never_registered_is_refused(self):
        other = self.make_repo("never-registered")
        r, body = self.get(f"/?t={TOKEN}&d={other}")
        self.assertEqual(r.status, 400)
        self.assertNotIn("secret-of-never-registered", body)

    def test_a_registered_repository_is_served(self):
        other = self.make_repo("registered-later")
        self.register(other)
        r, body = self.get(f"/?t={TOKEN}&d={other}")
        self.assertEqual(r.status, 200)
        self.assertIn("secret-of-registered-later", body)

    def test_the_registry_is_read_on_every_request(self):
        other = self.make_repo("added-while-running")
        self.assertEqual(self.get(f"/?t={TOKEN}&d={other}")[0].status, 400)
        self.register(other)
        self.assertEqual(self.get(f"/?t={TOKEN}&d={other}")[0].status, 200)

    def test_path_tricks_do_not_reach_other_repositories(self):
        other = self.make_repo("target")
        sub = os.path.join(self.repo, "..", "target")
        for d in (sub, other + "/", other + "/.", os.path.join(other, "..", "target"), "~", "/"):
            with self.subTest(d=d):
                self.assertEqual(self.get(f"/?t={TOKEN}&d={d}")[0].status, 400)

    def test_without_a_registry_nothing_is_served(self):
        reg = os.path.join(self.tmp.name, "state", "repos")
        os.rename(reg, reg + ".bak")
        try:
            self.assertEqual(self.get(f"/?t={TOKEN}&d={self.repo}")[0].status, 400)
        finally:
            os.rename(reg + ".bak", reg)

    def test_a_registered_path_that_is_no_longer_a_repo_is_refused(self):
        gone = os.path.join(self.tmp.name, "gone")
        os.makedirs(gone)          # registered but never a git repository
        self.register(gone)
        self.assertEqual(self.get(f"/?t={TOKEN}&d={gone}")[0].status, 400)

    def test_the_token_is_still_required_for_a_registered_repository(self):
        self.assertEqual(self.get(f"/?d={self.repo}")[0].status, 403)
        self.assertEqual(self.get(f"/?t={TOKEN}&d={self.repo}", host="evil.com")[0].status, 403)


class LegendAnchors(ServerBase):
    def help_page(self, lang=None):
        path = os.path.join(self.tmp.name, "state", "lang")
        if lang:
            with open(path, "w") as f:
                f.write(lang)
        try:
            return self.get(f"/help?t={TOKEN}")[1]
        finally:
            if os.path.exists(path):
                os.remove(path)

    def test_every_row_is_an_anchor(self):
        body = self.help_page()
        for ident in ("ctx", "limit-5h", "cost", "cost-subscription", "burn", "cache", "cache-expiry",
                      "cache-expired", "tokens", "staged", "warning", "more"):
            with self.subTest(id=ident):
                self.assertIn(f'<tr id="{ident}">', body)

    def test_anchors_are_the_same_in_every_language(self):
        import re
        ref = re.findall(r'<tr id="([^"]+)"', self.help_page())
        self.assertGreater(len(ref), 40)
        for code in ("es", "fr", "pt", "de"):
            with self.subTest(code=code):
                self.assertEqual(re.findall(r'<tr id="([^"]+)"', self.help_page(code)), ref)

    def test_the_targeted_row_is_highlighted_with_css_only(self):
        body = self.help_page()
        self.assertIn("tr:target", body)
        self.assertNotIn("<script", body)

    def test_the_intro_explains_the_links(self):
        self.assertIn("Cmd+click", self.help_page().split("<section>")[0])


if __name__ == "__main__":
    unittest.main()
