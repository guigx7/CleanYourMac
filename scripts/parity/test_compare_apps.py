import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
COMPARE = os.path.join(HERE, "compare_apps.py")


def write(obj):
    fd, path = tempfile.mkstemp(suffix=".json")
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f)
    return path


def report(apps=None, filters=None, updates=None, leftovers=None, installers=None):
    return {"apps": apps or [], "filters": filters or {"all": 1}, "updates": updates or [],
            "leftovers": {"leftoverFiles": leftovers or [], "installers": installers or []}}


def app(name, related=None, size=100):
    return {"name": name, "lastOpened": "2026-10-20", "size": size, "related": related or {}}


class CompareAppsTests(unittest.TestCase):
    def run_compare(self, base, ours):
        return subprocess.run([sys.executable, "-I", COMPARE, write(base), write(ours)], capture_output=True, text=True)

    def test_identical_passes(self):
        r = report(apps=[app("A.app", {"binaries": [{"name": "A.app", "size": 100}]})])
        out = self.run_compare(r, r)
        self.assertEqual(out.returncode, 0, out.stdout)

    def test_exact_lists_must_match(self):
        base = report(apps=[app("A.app"), app("B.app")], filters={"all": 2})
        self.assertEqual(self.run_compare(base, report(apps=[app("A.app")], filters={"all": 2})).returncode, 1)
        self.assertEqual(self.run_compare(base, report(apps=[app("A.app"), app("B.app")], filters={"all": 3})).returncode, 1)
        b2 = report(installers=[{"name": "x.dmg", "size": 10}])
        self.assertEqual(self.run_compare(b2, report()).returncode, 1)
        b3 = report(updates=[{"name": "GarageBand", "installed": "1"}])
        ours = report(updates=[{"name": "GarageBand", "source": "appStore"}, {"name": "macOS 27", "source": "macOS"}])
        self.assertEqual(self.run_compare(b3, ours).returncode, 0, "itens do macOS são divergência documentada")

    def test_related_is_subset(self):
        base = report(apps=[app("A.app", {"preferences": [{"name": "a.plist", "size": 4096}, {"name": "b.plist", "size": 4096}]})])
        fewer = report(apps=[app("A.app", {"preferences": [{"name": "a.plist", "size": 4096}]})])
        out = self.run_compare(base, fewer)
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("b.plist", out.stdout)
        more = report(apps=[app("A.app", {"preferences": [{"name": "a.plist", "size": 4096}, {"name": "c.plist", "size": 1}]})])
        self.assertEqual(self.run_compare(base, more).returncode, 1)

    def test_tolerance_one_percent_or_one_mb(self):
        base = report(apps=[app("A.app", {"preferences": [{"name": "a", "size": 500_000_000}]})])
        near = report(apps=[app("A.app", {"preferences": [{"name": "a", "size": 504_000_000}]})])
        far = report(apps=[app("A.app", {"preferences": [{"name": "a", "size": 520_000_000}]})])
        small = report(apps=[app("A.app", {"preferences": [{"name": "a", "size": 900_000}]})])
        small_base = report(apps=[app("A.app", {"preferences": [{"name": "a", "size": 100_000}]})])
        self.assertEqual(self.run_compare(base, near).returncode, 0)
        self.assertEqual(self.run_compare(base, far).returncode, 1)
        self.assertEqual(self.run_compare(small_base, small).returncode, 0)

    def test_duplicate_names_compared_as_lists(self):
        base = report(apps=[app("Z.app", {"supportingFiles": [{"name": "Zed", "size": 1_200_000_000}, {"name": "Zed", "size": 100}]})])
        ours = report(apps=[app("Z.app", {"supportingFiles": [{"name": "Zed", "size": 50}, {"name": "Zed", "size": 1_190_000_000}]})])
        self.assertEqual(self.run_compare(base, ours).returncode, 0)

    def test_display_rounding_tolerated(self):
        # "1,5 GB" na tela do CleanMyMac pode ser de 1,45 a 1,55 GB.
        base = report(apps=[app("C.app", {"preferences": [{"name": "c", "size": 1_500_000_000}]})])
        ours = report(apps=[app("C.app", {"preferences": [{"name": "c", "size": 1_450_400_000}]})])
        self.assertEqual(self.run_compare(base, ours).returncode, 0)

    def test_bundle_size_is_a_note(self):
        # O CleanMyMac mede o bundle pelo Spotlight (pode estar velho): diferença no bundle é nota, não falha.
        base = report(apps=[app("G.app", {"binaries": [{"name": "G.app", "size": 22_100_000}]})])
        ours = report(apps=[app("G.app", {"binaries": [{"name": "G.app", "size": 32_500_000}]})])
        out = self.run_compare(base, ours)
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertIn("nota", out.stdout)

    def test_known_leftover_name_aliases(self):
        base = report(leftovers=[{"name": "Thumbnail Extension", "size": 24600}])
        ours = report(leftovers=[{"name": "ThumbnailShareExtension (Global)", "size": 24576}])
        aliases = write({"leftoverNames": {"Thumbnail Extension": "ThumbnailShareExtension (Global)"}})
        out = subprocess.run([sys.executable, "-I", COMPARE, write(base), write(ours), aliases], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout)
        self.assertEqual(self.run_compare(base, ours).returncode, 1)


if __name__ == "__main__":
    unittest.main()
