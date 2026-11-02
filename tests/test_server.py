"""Pruebas de seguridad y comportamiento de diffserver.py (solo biblioteca estándar)."""
import http.client
import importlib
import os
import socket
import subprocess
import sys
import tempfile
import threading
import unittest

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOKEN = "t0k3n-de-prueba"


def puerto_libre():
    with socket.socket() as s:
        s.bind(("127.0.0.1", 0))
        return s.getsockname()[1]


class ServidorBase(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory()
        cls.puerto = puerto_libre()
        os.makedirs(os.path.join(cls.tmp.name, "estado"))
        with open(os.path.join(cls.tmp.name, "estado", "token"), "w") as f:
            f.write(TOKEN)
        os.environ["STATUSLINE_PORT"] = str(cls.puerto)
        os.environ["STATUSLINE_STATE"] = os.path.join(cls.tmp.name, "estado")
        sys.path.insert(0, RAIZ)
        sys.modules.pop("diffserver", None)
        cls.mod = importlib.import_module("diffserver")
        cls.srv = cls.mod.ThreadingHTTPServer(("127.0.0.1", cls.puerto), cls.mod.H)
        threading.Thread(target=cls.srv.serve_forever, daemon=True).start()

        # Repo git de prueba con ficheros "difíciles"
        cls.repo = os.path.join(cls.tmp.name, "repo")
        os.makedirs(cls.repo)
        run = lambda *a: subprocess.run(["git", "-C", cls.repo, *a], check=True, capture_output=True)
        run("init", "-q")
        run("config", "user.email", "t@example.com")
        run("config", "user.name", "t")
        with open(os.path.join(cls.repo, "a.txt"), "w") as f:
            f.write("uno\n")
        run("add", "-A")
        run("commit", "-q", "-m", "inicial")
        with open(os.path.join(cls.repo, "a.txt"), "w") as f:
            f.write("dos\n")
        cls.nombre_xss = "<img src=x onerror=alert(1)>.txt"
        with open(os.path.join(cls.repo, cls.nombre_xss), "w") as f:
            f.write("<script>alert(1)</script>\n")

    @classmethod
    def tearDownClass(cls):
        cls.srv.shutdown()
        cls.srv.server_close()
        cls.tmp.cleanup()

    def get(self, ruta, host=None):
        c = http.client.HTTPConnection("127.0.0.1", self.puerto, timeout=15)
        c.putrequest("GET", ruta, skip_host=True)
        c.putheader("Host", f"127.0.0.1:{self.puerto}" if host is None else host)
        c.endheaders()
        r = c.getresponse()
        cuerpo = r.read().decode(errors="replace")
        c.close()
        return r, cuerpo


class Autenticacion(ServidorBase):
    def test_sin_token_403(self):
        self.assertEqual(self.get("/ayuda")[0].status, 403)

    def test_token_incorrecto_403(self):
        self.assertEqual(self.get("/ayuda?t=otro")[0].status, 403)

    def test_token_vacio_403(self):
        self.assertEqual(self.get("/ayuda?t=")[0].status, 403)

    def test_token_correcto_200(self):
        self.assertEqual(self.get(f"/ayuda?t={TOKEN}")[0].status, 200)

    def test_diff_sin_token_no_filtra_nada(self):
        r, cuerpo = self.get(f"/?d={self.repo}")
        self.assertEqual(r.status, 403)
        self.assertNotIn("dos", cuerpo)

    def test_sin_fichero_de_token_siempre_403(self):
        os.rename(os.path.join(self.tmp.name, "estado", "token"), os.path.join(self.tmp.name, "estado", "token.bak"))
        try:
            self.assertEqual(self.get("/ayuda?t=")[0].status, 403)
        finally:
            os.rename(os.path.join(self.tmp.name, "estado", "token.bak"), os.path.join(self.tmp.name, "estado", "token"))


class AntiRebinding(ServidorBase):
    def test_host_ajeno_403_aunque_el_token_sea_bueno(self):
        for host in ("evil.com", f"evil.com:{self.puerto}", f"127.0.0.1.evil.com:{self.puerto}", "", "127.0.0.1:1"):
            with self.subTest(host=host):
                self.assertEqual(self.get(f"/ayuda?t={TOKEN}", host=host)[0].status, 403)

    def test_localhost_permitido(self):
        self.assertEqual(self.get(f"/ayuda?t={TOKEN}", host=f"localhost:{self.puerto}")[0].status, 200)


class Contenido(ServidorBase):
    def test_cabeceras_de_seguridad(self):
        r, _ = self.get(f"/ayuda?t={TOKEN}")
        self.assertIn("default-src 'none'", r.getheader("Content-Security-Policy"))
        self.assertEqual(r.getheader("X-Content-Type-Options"), "nosniff")
        self.assertEqual(r.getheader("Referrer-Policy"), "no-referrer")
        self.assertEqual(r.getheader("Cache-Control"), "no-store")

    def test_ayuda_muestra_version(self):
        _, cuerpo = self.get(f"/ayuda?t={TOKEN}")
        self.assertIn(self.mod.VERSION, cuerpo)

    def test_directorio_que_no_es_repo_400(self):
        self.assertEqual(self.get(f"/?t={TOKEN}&d={self.tmp.name}")[0].status, 400)

    def test_directorio_inexistente_400(self):
        self.assertEqual(self.get(f"/?t={TOKEN}&d=/no/existe")[0].status, 400)

    def test_diff_de_repo_ok(self):
        r, cuerpo = self.get(f"/?t={TOKEN}&d={self.repo}")
        self.assertEqual(r.status, 200)
        self.assertIn("dos", cuerpo)

    def test_nombres_de_fichero_se_escapan(self):
        _, cuerpo = self.get(f"/?t={TOKEN}&d={self.repo}")
        self.assertNotIn("<img src=x", cuerpo)
        self.assertNotIn("<script>alert", cuerpo)
        self.assertIn("&lt;img src=x", cuerpo)

    def test_diff_enorme_se_trunca(self):
        grande = os.path.join(self.repo, "grande.txt")
        with open(grande, "w") as f:
            f.write("x" * (self.mod.MAX_DIFF + 4096) + "\n")
        try:
            r, cuerpo = self.get(f"/?t={TOKEN}&d={self.repo}")
            self.assertEqual(r.status, 200)
            self.assertIn("diff truncado", cuerpo)
        finally:
            os.remove(grande)


if __name__ == "__main__":
    unittest.main()
