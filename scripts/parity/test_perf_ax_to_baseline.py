import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERT = os.path.join(HERE, "perf_ax_to_baseline.py")
FIXTURE = os.path.join(HERE, "fixtures", "perf-ax")


class PerfAxToBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fd, out = tempfile.mkstemp(suffix=".json"); os.close(fd)
        r = subprocess.run([sys.executable, "-I", CONVERT, FIXTURE, out], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        with open(out, encoding="utf-8") as f:
            cls.b = json.load(f)

    def test_maintenance_tasks_in_order(self):
        self.assertEqual(self.b["tasks"], ["Acelerar o Mail", "Esvaziar Cache do DNS", "Liberar Espaço Purgável",
                                           "Reindexar o Spotlight", "Reparar Permissões do Disco"])

    def test_purgeable_subtitle_in_bytes(self):
        self.assertEqual(self.b["purgeable"], 3_800_000_000)

    def test_login_items(self):
        self.assertEqual(self.b["loginItems"], ["GlucoTracker.app", "Hidden Bar.app", "Vorssaint.app", "Warp.app"])

    def test_background_items(self):
        items = self.b["backgroundItems"]
        self.assertEqual(len(items), 9)
        self.assertIn("com.bjango.istatmenus.installer.plist", items)
        self.assertEqual(items.count("Logi Options+.app"), 2)

    def test_result_tiles(self):
        self.assertEqual(self.b["tiles"], {"loginItems": 4, "maintenance": 5, "backgroundItems": 9})


if __name__ == "__main__":
    unittest.main()
