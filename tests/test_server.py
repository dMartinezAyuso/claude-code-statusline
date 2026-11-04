"""Security and behaviour tests for diffserver.py (standard library only)."""
import http.client
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


if __name__ == "__main__":
    unittest.main()
