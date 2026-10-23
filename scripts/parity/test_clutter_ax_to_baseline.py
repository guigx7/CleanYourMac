import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERT = os.path.join(HERE, "clutter_ax_to_baseline.py")
FIXTURE = os.path.join(HERE, "fixtures", "clutter-ax")


class ClutterAxToBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fd, out = tempfile.mkstemp(suffix=".json"); os.close(fd)
        r = subprocess.run([sys.executable, "-I", CONVERT, FIXTURE, out], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        with open(out, encoding="utf-8") as f:
            cls.b = json.load(f)

    def test_results_header_and_tiles(self):
        self.assertEqual(self.b["total"], 885)
        self.assertEqual(self.b["tiles"], [
            {"text": "13 Imagens Similares Novas Encontradas", "detail": "15,9 MB de fotos praticamente idênticas apareceram no Mac nos últimos 30 dias. Dê uma olhada!"},
            {"text": "45 Arquivos Duplicados Encontrados em Documentos", "detail": "Remova 35,6 MB de cópias desnecessárias para economizar espaço."},
            {"text": "591 MB de Downloads do Google Chrome Encontrados", "detail": "Revise e remova os downloads desnecessários para recuperar um espaço significativo."},
        ])

    def test_large_old_files(self):
        files = self.b["largeOld"]
        self.assertEqual([f["name"] for f in files][:2], ["Vídeo HG - Volume +.mov", "HG Vídeo Final -.MOV"])
        self.assertEqual(len(files), 5)
        self.assertEqual(files[0], {"name": "Vídeo HG - Volume +.mov", "folder": "guigx/Downloads", "lastOpened": "2026-08-06",
                                    "size": 1_000_000_000})

    def test_duplicates_groups(self):
        groups = self.b["duplicates"]
        self.assertEqual(len(groups), 149)
        self.assertEqual(groups[0], {"name": "SwiftUICore-3GNUPH84KUW7I.swiftmodule", "size": 13_000_000, "count": 3})

    def test_similar_groups(self):
        groups = self.b["similar"]
        self.assertEqual(len(groups), 65)
        self.assertEqual(groups[0], {"date": "2024-09-04", "size": 8_200_000, "count": 6})

    def test_downloads(self):
        d = self.b["downloads"]
        self.assertEqual(d["groups"], {"Google Chrome": 591_000_000, "Slack": 0, "Safari": 0})
        self.assertEqual(d["files"][0], {"name": "Godot_v4.7.2-stable_macos.universal.zip", "size": 185_000_000})


if __name__ == "__main__":
    unittest.main()
