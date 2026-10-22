import importlib.util, os, unittest, copy

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("compare_spacelens", os.path.join(HERE, "compare_spacelens.py"))
cs = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cs)

GB = 1_000_000_000
BASE = {"volume": {"used": 225 * GB, "capacity": 494 * GB},
        "folders": {"root": {"size": 242 * GB, "items": 3_000_000, "children": [["Users", 183 * GB], ["System", 19_900_000_000]],
                             "others": 0, "purgeable": 3_900_000_000}}}
OURS = {"volume": {"used": 225_261_693_715, "capacity": 494_332_366_848},
        "folders": {"root": {"size": 241_800_000_000, "items": 3_587_086, "children": [["Users", 183_200_000_000], ["System", 19_930_000_000]],
                             "others": 12_000, "purgeable": 3_870_000_000}}}


class CompareSpaceLensTests(unittest.TestCase):
    def test_within_display_rounding(self):
        failures, _ = cs.compare(BASE, OURS, {})
        self.assertEqual(failures, [])

    def test_one_decimal_below_100(self):
        # A tela mostra "2,4 GB" para 2,35–2,45 GB (uma casa decimal abaixo de 100 unidades).
        self.assertTrue(cs.close(2_400_000_000, 2_440_000_000))
        self.assertTrue(cs.close(225_000_000_000, 225_480_000_000, 0))
        self.assertFalse(cs.close(8_200_000_000, 8_400_000_000))

    def test_size_out_of_tolerance_fails(self):
        ours = copy.deepcopy(OURS)
        ours["folders"]["root"]["children"][1][1] = 22_100_000_000
        failures, _ = cs.compare(BASE, ours, {})
        self.assertTrue(any("System" in f for f in failures))

    def test_names_and_order(self):
        ours = copy.deepcopy(OURS)
        ours["folders"]["root"]["children"].append(["opt", 3_800_000_000])
        self.assertTrue(any("opt" in f for f in cs.compare(BASE, ours, {})[0]))
        known = {"children": {"root/opt": "motivo"}}
        failures, notes = cs.compare(BASE, ours, known)
        self.assertEqual(failures, [])
        self.assertTrue(any("opt" in n for n in notes))

    def test_item_count_rounding(self):
        ours = copy.deepcopy(OURS)
        ours["folders"]["root"]["items"] = 4_200_000
        self.assertTrue(any("items" in f for f in cs.compare(BASE, ours, {})[0]))

    def test_missing_folder_is_note(self):
        base = copy.deepcopy(BASE)
        base["folders"]["home"] = {"size": GB, "items": 10, "children": [], "others": None, "purgeable": None}
        failures, notes = cs.compare(base, OURS, {})
        self.assertTrue(any("home" in f for f in failures))


if __name__ == "__main__":
    unittest.main()
