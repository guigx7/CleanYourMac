import importlib.util, os, unittest, copy

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("compare_clutter", os.path.join(HERE, "compare_clutter.py"))
cc = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cc)

BASE = {
    "total": 10,
    "tiles": [{"text": "13 Imagens Similares Novas Encontradas", "detail": "15,9 MB de fotos praticamente idênticas."},
              {"text": "45 Arquivos Duplicados Encontrados em Documentos", "detail": "Remova 35,6 MB de cópias."},
              {"text": "591 MB de Downloads do Google Chrome Encontrados", "detail": "Revise."}],
    "largeOld": [{"name": "Vídeo.mov", "folder": "me/Downloads", "lastOpened": "2026-08-06", "size": 1_000_000_000}],
    "duplicates": [{"name": "BIOMECÂNICA (1).png", "size": 2_400_000, "count": 2}],
    "similar": [{"date": "2024-09-04", "size": 8_200_000, "count": 6}],
    "downloads": {"groups": {"Google Chrome": 591_000_000, "Slack": 0}, "files": [{"name": "a.zip", "size": 185_000_000}]},
}
# Mesmo nome em NFD, como vem do disco.
OURS = {
    "total": 12,
    "tiles": [{"kind": "similarRecent", "count": 91, "size": 58_000_000, "app": None},
              {"kind": "duplicatesDocuments", "count": 45, "size": 35_602_370, "app": None},
              {"kind": "downloads", "count": 1, "size": 573_447_589, "app": "Google Chrome"}],
    "largeOld": [{"name": "Vídeo.mov", "folder": "me/Downloads", "lastOpened": "2026-08-06", "size": 1_003_000_000}],
    "duplicates": [{"name": "BIOMECÂNICA (1).png", "size": 2_412_000, "count": 2}],
    "similar": [{"date": "2024-09-04", "size": 8_210_151, "count": 6}],
    "downloads": {"groups": {"Google Chrome": 573_447_589}, "files": [{"name": "a.zip", "size": 170_622_178}]},
}


class CompareClutterTests(unittest.TestCase):
    def test_baseline_shape_passes(self):
        failures, notes = cc.compare(BASE, OURS, {})
        self.assertEqual(failures, [])
        self.assertTrue(any("Similares" in n for n in notes))
        self.assertTrue(any("Slack" in n for n in notes))

    def test_tile_parsing(self):
        self.assertEqual(cc.tile_info(BASE["tiles"][1]), ("duplicates", 45, 35_600_000))
        self.assertEqual(cc.tile_info(BASE["tiles"][2]), ("downloads", None, 591_000_000))

    def test_duplicate_title_mismatch_fails(self):
        ours = copy.deepcopy(OURS)
        ours["duplicates"][0]["name"] = "BIOMECÂNICA.png"
        failures, _ = cc.compare(BASE, ours, {})
        self.assertTrue(any("BIOMECÂNICA" in f for f in failures))
        failures, notes = cc.compare(BASE, ours, {"duplicates": {"BIOMECÂNICA.png": "motivo", "BIOMECÂNICA (1).png": "motivo"}})
        self.assertEqual(failures, [])

    def test_downloads_tolerance(self):
        ours = copy.deepcopy(OURS)
        ours["downloads"]["groups"]["Google Chrome"] = 520_000_000
        self.assertTrue(any("Google Chrome" in f for f in cc.compare(BASE, ours, {})[0]))

    def test_tile_count_and_size(self):
        ours = copy.deepcopy(OURS)
        ours["tiles"][1]["size"] = 17_979_241
        self.assertTrue(any("duplicatesDocuments" in f for f in cc.compare(BASE, ours, {})[0]))
        ours = copy.deepcopy(OURS)
        ours["tiles"][0]["count"] = 5
        self.assertEqual(cc.compare(BASE, ours, {})[0], [])  # Similares: só nota

    def test_large_old_missing_fails(self):
        ours = copy.deepcopy(OURS)
        ours["largeOld"] = []
        self.assertTrue(any("Fundo do Baú" in f for f in cc.compare(BASE, ours, {})[0]))


if __name__ == "__main__":
    unittest.main()
