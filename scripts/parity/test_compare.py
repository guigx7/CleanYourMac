import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.join(HERE, "compare.py")


def write(obj):
    f = tempfile.NamedTemporaryFile("w", suffix=".json", delete=False)
    json.dump(obj, f)
    f.close()
    return f.name


def report(groups):
    return {"cmmVersion": "5.7.2", "groups": {g: {"totalBytes": t, "items": items} for g, (t, items) in groups.items()}}


class CompareTests(unittest.TestCase):
    def run_compare(self, base, ours):
        return subprocess.run([sys.executable, "-I", COMPARE, write(base), write(ours)], capture_output=True, text=True)

    def test_identical_passes(self):
        r = report({"userCache": (2_800_000_000, [{"name": "Google", "bytes": 1_600_000_000, "recommended": True}])})
        out = self.run_compare(r, r)
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("userCache", out.stdout)

    def test_ten_percent_fails(self):
        base = report({"userLogs": (100_000_000, [])})
        ours = report({"userLogs": (110_000_000, [])})
        out = self.run_compare(base, ours)
        self.assertEqual(out.returncode, 1)
        self.assertIn("userLogs", out.stdout)

    def test_small_absolute_difference_tolerated(self):
        base = report({"systemLogs": (10_100_000, [])})
        ours = report({"systemLogs": (12_000_000, [])})
        self.assertEqual(self.run_compare(base, ours).returncode, 0)

    def test_lists_items_only_on_one_side(self):
        base = report({"userCache": (10, [{"name": "A", "bytes": 10, "recommended": False}])})
        ours = report({"userCache": (10, [{"name": "B", "bytes": 10, "recommended": False}])})
        out = self.run_compare(base, ours)
        self.assertIn("só CMM: A", out.stdout)
        self.assertIn("só cym: B", out.stdout)


if __name__ == "__main__":
    unittest.main()
