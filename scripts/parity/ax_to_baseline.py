#!/usr/bin/env python3
"""Converte os dumps de Acessibilidade de collect-baseline.sh em uma baseline JSON.

Uso: python3 -I scripts/parity/ax_to_baseline.py <pasta baseline-AAAAMMDD-HHMM> <saída.json>
"""
import json, os, re, sys
from datetime import datetime, timezone

GROUPS = {
    "Arquivos de Cache do Usuário": "userCache", "Arquivos de Cache do Sistema": "systemCache",
    "Binários Universais": "universalBinaries", "Arquivos de Registro do Usuário": "userLogs",
    "Arquivos de Registro do Sistema": "systemLogs", "Arquivos de Idioma": "languageFiles",
    "Itens de Início Defeituosos": "brokenLoginItems", "Versões de Documentos": "documentVersions",
    "Usuários Apagados": "deletedUsers", "Preferências Defeituosas": "brokenPreferences",
    "Backups de Dispositivos iOS": "iosBackups", "Detritos do Xcode": "xcodeJunk",
    "Detritos de IA": "aiAgentsJunk", "Modelos locais": "localModels",
}
UNITS = {"KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}


def to_bytes(text):
    m = re.match(r"^\s*([\d.,]+)\s*(KB|MB|GB|TB)\s*$", text)
    if not m:
        return None
    return int(round(float(m.group(1).replace(".", "").replace(",", ".")) * UNITS[m.group(2)]))


def text_of(line):
    return line.split(":", 1)[1].strip() if ":" in line else ""


def parse_group(path):
    lines = open(path, encoding="utf-8").read().splitlines()
    items, current = [], None
    for line in lines:
        s = line.strip()
        if s.startswith("AXCell:"):
            current = {"name": text_of(s), "bytes": 0, "recommended": False}
            items.append(current)
        elif current and s.startswith("AXCheckBox"):
            current["recommended"] = "[checked=1]" in s
        elif current and s.startswith("AXStaticText:") and "Tamanho total ou contagem" in s:
            b = to_bytes(text_of(s).split("|")[0])
            if b is not None:
                current["bytes"] = b
    return items


def main(folder, out):
    groups = {}
    for category in os.listdir(folder):
        cat_dir = os.path.join(folder, category)
        if not os.path.isdir(cat_dir):
            continue
        cat = os.path.join(cat_dir, "_category.txt")
        totals = {}
        if os.path.exists(cat):
            lines = [l.strip() for l in open(cat, encoding="utf-8")]
            for prev, line in zip(lines, lines[1:]):
                if "Tamanho total dos itens no grupo" in line:
                    name = text_of(prev).split("|")[0].strip()
                    totals[name] = to_bytes(text_of(line).split("|")[0]) or 0
        for name, gid in GROUPS.items():
            f = os.path.join(cat_dir, name + ".txt")
            if name in totals or os.path.exists(f):
                groups[gid] = {"totalBytes": totals.get(name, 0), "items": parse_group(f) if os.path.exists(f) else []}
    data = {"cmmVersion": "5.7.2", "capturedAt": datetime.now(timezone.utc).isoformat(timespec="seconds"), "groups": groups}
    json.dump(data, open(out, "w", encoding="utf-8"), ensure_ascii=False, indent=2)
    print(f"{len(groups)} grupos, {sum(len(g['items']) for g in groups.values())} itens → {out}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
