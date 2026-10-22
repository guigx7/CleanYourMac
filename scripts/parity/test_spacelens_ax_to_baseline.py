import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERT = os.path.join(HERE, "spacelens_ax_to_baseline.py")
FIXTURE = os.path.join(HERE, "fixtures", "spacelens-ax")


class SpaceLensAxToBaselineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        fd, out = tempfile.mkstemp(suffix=".json"); os.close(fd)
        r = subprocess.run([sys.executable, "-I", CONVERT, FIXTURE, out], capture_output=True, text=True)
        assert r.returncode == 0, r.stderr
        with open(out, encoding="utf-8") as f:
            cls.b = json.load(f)

    def test_volume_usage(self):
        self.assertEqual(self.b["volume"], {"used": 225_000_000_000, "capacity": 494_000_000_000})

    def test_root_folder(self):
        root = self.b["folders"]["root"]
        self.assertEqual(root["size"], 242_000_000_000)
        self.assertEqual(root["items"], 3_000_000)
        self.assertEqual(root["children"][:3], [["Users", 183_000_000_000], ["System", 19_900_000_000], ["Applications", 15_800_000_000]])
        self.assertEqual(len(root["children"]), 9)
        self.assertEqual(root["others"], 0)
        self.assertEqual(root["purgeable"], 3_900_000_000)

    def test_users_and_home(self):
        self.assertEqual(self.b["folders"]["users"]["children"], [["guigx", 183_000_000_000], ["Shared", 123_000], [".localized", 0]])
        home = self.b["folders"]["home"]
        self.assertEqual(home["items"], 2_000_000)
        self.assertEqual([c[0] for c in home["children"]], ["Library", "Projetos", ".colima", ".npm", ".claude", "Downloads", ".cache"])
        self.assertEqual(home["others"], 9_300_000_000)
        self.assertIsNone(home["purgeable"])


if __name__ == "__main__":
    unittest.main()
