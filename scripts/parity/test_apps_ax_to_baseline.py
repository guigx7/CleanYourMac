import json, os, subprocess, sys, tempfile, unittest

HERE = os.path.dirname(os.path.abspath(__file__))
CONVERT = os.path.join(HERE, "apps_ax_to_baseline.py")
FIXTURE = os.path.join(HERE, "fixtures", "apps-ax")

APP_DETAIL = """\
            AXCell: Discord.app
              AXCheckBox [checked=0]:
              AXStaticText: Discord.app | Discord.app
              AXStaticText: 25 de set. de 2026 | O dia em que você abriu o aplicativo pela última vez
              AXStaticText: 1,5 GB | Tamanho total ou contagem dos itens incluídos
              AXButton: Oculte os itens incluídos
            AXCell: Binários
              AXCheckBox [checked=0]:
              AXStaticText: Binários | Binários
              AXButton: Oculte os itens incluídos
            AXCell: Discord.app
              AXCheckBox [checked=0]:
              AXStaticText: Discord.app | Discord.app
              AXStaticText: 293 MB | Tamanho total ou contagem dos itens incluídos
            AXCell: Arquivos de Suporte
              AXCheckBox [checked=0]:
              AXStaticText: Arquivos de Suporte | Arquivos de Suporte
              AXButton: Oculte os itens incluídos
            AXCell: discord
              AXCheckBox [checked=0]:
              AXStaticText: discord | discord
              AXStaticText: 1,2 GB | Tamanho total ou contagem dos itens incluídos
            AXCell: GarageBand.app
              AXCheckBox [checked=0]:
              AXStaticText: GarageBand.app | GarageBand.app
              AXStaticText: 5 de mar. de 2026 | O dia em que você abriu o aplicativo pela última vez
              AXStaticText: 2,2 GB | Tamanho total ou contagem dos itens incluídos
"""


class AppsAxToBaselineTests(unittest.TestCase):
    def convert(self, folder):
        fd, out = tempfile.mkstemp(suffix=".json"); os.close(fd)
        r = subprocess.run([sys.executable, "-I", CONVERT, folder, out], capture_output=True, text=True)
        self.assertEqual(r.returncode, 0, r.stderr)
        with open(out, encoding="utf-8") as f:
            return json.load(f)

    def test_lists_apps_with_dates_and_sizes(self):
        b = self.convert(FIXTURE)
        self.assertEqual(len(b["apps"]), 26)
        bruno = next(a for a in b["apps"] if a["name"] == "Bruno.app")
        self.assertEqual(bruno["lastOpened"], "2026-08-20")
        self.assertEqual(bruno["size"], 525_000_000)

    def test_filter_counts(self):
        f = self.convert(FIXTURE)["filters"]
        self.assertEqual(f, {"all": 26, "unused": 1, "suspicious": 0, "selected": 0, "appStore": 3, "setapp": 1,
                             "storeOther": 22, "apple": 2, "google": 1, "macPaw": 2, "microsoft": 1,
                             "vendorOther": 20, "audioPlugins": 1})

    def test_related_files_by_kind(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(FIXTURE, "uninstaller.txt"), encoding="utf-8") as src, \
                open(os.path.join(d, "uninstaller.txt"), "w", encoding="utf-8") as dst:
            dst.write(src.read())
        with open(os.path.join(d, "app-Discord.app.txt"), "w", encoding="utf-8") as f:
            f.write(APP_DETAIL)
        discord = next(a for a in self.convert(d)["apps"] if a["name"] == "Discord.app")
        self.assertEqual(discord["related"], {
            "binaries": [{"name": "Discord.app", "size": 293_000_000}],
            "supportingFiles": [{"name": "discord", "size": 1_200_000_000}],
        })

    def test_related_uses_levels_when_present(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(FIXTURE, "uninstaller.txt"), encoding="utf-8") as src, \
                open(os.path.join(d, "uninstaller.txt"), "w", encoding="utf-8") as dst:
            dst.write(src.read())
        with open(os.path.join(d, "app-GarageBand.app.txt"), "w", encoding="utf-8") as f:
            f.write(GARAGEBAND_LEVELS)
        gb = next(a for a in self.convert(d)["apps"] if a["name"] == "GarageBand.app")
        self.assertEqual(gb["related"], {"container": [{"name": "com.apple.garageband10", "size": 4100}],
                                         "binaries": [{"name": "GarageBand.app", "size": 2_200_000_000}]})

    def test_prefers_all_apps_filter_dump(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(FIXTURE, "uninstaller.txt"), encoding="utf-8") as src:
            full = src.read()
        with open(os.path.join(d, "filter-Todos os Aplicativos.txt"), "w", encoding="utf-8") as f:
            f.write(full)
        with open(os.path.join(d, "uninstaller.txt"), "w", encoding="utf-8") as f:
            f.write(APP_DETAIL)  # uma vista filtrada, com só 2 apps
        self.assertEqual(len(self.convert(d)["apps"]), 26)

    def test_leftovers_tree_by_level(self):
        d = tempfile.mkdtemp()
        with open(os.path.join(d, "leftovers-Arquivos de Sobras.txt"), "w", encoding="utf-8") as f:
            f.write(LEFTOVERS)
        self.assertEqual(self.convert(d)["leftovers"]["leftoverFiles"], [
            {"name": "Thumbnail Extension", "size": 24600,
             "related": {"container": [{"name": "com.canva.affinity.thumbnail", "size": 24600}]}},
            {"name": "com.example.Gone", "size": 0, "related": {}},
        ])


GARAGEBAND_LEVELS = """\
          AXRow [level=0]: 
            AXCell: GarageBand.app
              AXStaticText: 5 de mar. de 2026 | O dia em que você abriu o aplicativo pela última vez
              AXStaticText: 2,2 GB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=1]: 
            AXCell: Contêiner
          AXRow [level=2]: 
            AXCell: com.apple.garageband10
              AXStaticText: 4,1 KB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=3]: 
            AXCell: Preferências
          AXRow [level=4]: 
            AXCell: com.apple.garageband10.plist
              AXStaticText: 4,1 KB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=1]: 
            AXCell: Binários
          AXRow [level=2]: 
            AXCell: GarageBand.app
              AXStaticText: 2,2 GB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=0]: 
            AXCell: GlucoTracker.app
              AXStaticText: 20 de out. de 2026 | O dia em que você abriu o aplicativo pela última vez
"""


LEFTOVERS = """\
          AXRow [level=0]: 
            AXCell: Thumbnail Extension
              AXStaticText: 24,6 KB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=1]: 
            AXCell: Contêiner
          AXRow [level=2]: 
            AXCell: com.canva.affinity.thumbnail
              AXStaticText: 24,6 KB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=3]: 
            AXCell: Dados de Usuário
          AXRow [level=4]: 
            AXCell: tmp
              AXStaticText: 0 KB | Tamanho total ou contagem dos itens incluídos
          AXRow [level=0]: 
            AXCell: com.example.Gone
              AXStaticText: 0 KB | Tamanho total ou contagem dos itens incluídos
"""


if __name__ == "__main__":
    unittest.main()
