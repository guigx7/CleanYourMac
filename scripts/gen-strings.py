#!/usr/bin/env python3
"""Gera App/Resources/Localizable.xcstrings a partir de App/Resources/Strings.tsv.

Formato do TSV: chave<TAB>en<TAB>pt-BR (linhas vazias e começando com # são ignoradas).
Use \\n para quebra de linha. Uso: python3 -I scripts/gen-strings.py
"""
import json, pathlib, sys

root = pathlib.Path(__file__).resolve().parent.parent
src = root / "App/Resources/Strings.tsv"
dst = root / "App/Resources/Localizable.xcstrings"

strings = {}
for n, line in enumerate(src.read_text(encoding="utf-8").splitlines(), 1):
    if not line.strip() or line.startswith("#"):
        continue
    parts = line.split("\t")
    if len(parts) != 3:
        sys.exit(f"{src.name}:{n}: esperado 3 colunas, achei {len(parts)}")
    key, en, pt = (p.replace("\\n", "\n") for p in parts)
    if key in strings:
        sys.exit(f"{src.name}:{n}: chave duplicada {key}")
    strings[key] = {
        "extractionState": "manual",
        "localizations": {
            "en": {"stringUnit": {"state": "translated", "value": en}},
            "pt-BR": {"stringUnit": {"state": "translated", "value": pt}},
        },
    }

catalog = {"sourceLanguage": "en", "strings": dict(sorted(strings.items())), "version": "1.0"}
dst.write_text(json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
print(f"{len(strings)} chaves → {dst.relative_to(root)}")
