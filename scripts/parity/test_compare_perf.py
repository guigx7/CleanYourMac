import importlib.util, os, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("compare_perf", os.path.join(HERE, "compare_perf.py"))
cp = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cp)

BASE = {"tasks": ["Acelerar o Mail", "Esvaziar Cache do DNS", "Liberar Espaço Purgável"], "purgeable": 3_800_000_000,
        "loginItems": ["Warp.app"], "backgroundItems": ["Logi Options+.app", "Logi Options+.app", "x.plist"],
        "tiles": {"loginItems": 1, "maintenance": 3, "backgroundItems": 3}}
OURS = {"tasks": ["speedUpMail", "flushDNS", "freeUpPurgeable"], "purgeable": 3_900_000_000,
        "loginItems": ["Warp.app"], "backgroundItems": ["Logi Options+.app", "Logi Options+.app", "x.plist"],
        "tiles": {"loginItems": 1, "maintenance": 3, "backgroundItems": 3}}


class ComparePerfTests(unittest.TestCase):
    def test_exact_task_lists(self):
        failures, notes = cp.compare(BASE, OURS, {})
        self.assertEqual(failures, [])
        # Purgável muda entre análises: diferença é nota.
        self.assertTrue(any("purgeable" in n for n in notes))
        ours = dict(OURS, tasks=["speedUpMail", "flushDNS"])
        failures, _ = cp.compare(BASE, ours, {})
        self.assertTrue(any("freeUpPurgeable" in f for f in failures))
        ours = dict(OURS, tiles=dict(OURS["tiles"], maintenance=2))
        self.assertTrue(cp.compare(BASE, ours, {})[0])

    def test_exact_startup_items(self):
        ours = dict(OURS, backgroundItems=["Logi Options+.app", "x.plist"])
        failures, _ = cp.compare(BASE, ours, {})
        self.assertTrue(any("Logi Options+.app" in f for f in failures))
        ours = dict(OURS, loginItems=["Warp.app", "Extra.app"])
        self.assertTrue(any("Extra.app" in f for f in cp.compare(BASE, ours, {})[0]))

    def test_known_divergences_are_notes(self):
        ours = dict(OURS, backgroundItems=["Logi Options+.app", "Logi Options+.app", "x.plist", "y.plist"],
                    tiles=dict(OURS["tiles"], backgroundItems=4))
        known = {"backgroundItems": {"y.plist": "motivo"}, "tiles": {"backgroundItems": "y.plist a mais"}}
        failures, notes = cp.compare(BASE, ours, known)
        self.assertEqual(failures, [])
        self.assertTrue(any("y.plist" in n for n in notes))


if __name__ == "__main__":
    unittest.main()
