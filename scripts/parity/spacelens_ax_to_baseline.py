#!/usr/bin/env python3
"""Converte os dumps da Lupa de Espaço do CleanMyMac em uma baseline JSON.

Uso: python3 -I scripts/parity/spacelens_ax_to_baseline.py <pasta> <saída.json>
A pasta tem um dump por pasta visitada (root.txt, users.txt, home.txt…); a chave em "folders" é o nome do arquivo.
"""
import json, os, re, sys

UNITS = {"bytes": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
COUNT = {"": 1, "K": 1e3, "M": 1e6}


def to_bytes(text):
    m = re.match(r"^\s*([\d.,]+)\s*(bytes|KB|MB|GB|TB)\s*$", text)
    if not m:
        return None
    return int(round(float(m.group(1).replace(".", "").replace(",", ".")) * UNITS[m.group(2)]))


def text(line):
    s = line.strip()
    return s.split(": ", 1)[1] if ": " in s else ""


def convert_folder(lines):
    out = {"size": None, "items": None, "children": [], "others": None, "purgeable": None}
    usage = None
    for i, line in enumerate(lines):
        s = line.strip()
        m = re.match(r"^AXStaticText: (.+) de (.+) usados$", s)
        if m and usage is None:
            usage = {"used": to_bytes(m.group(1)), "capacity": to_bytes(m.group(2))}
            # Depois de "usados": nome da pasta, tamanho e "N itens".
            out["size"] = to_bytes(text(lines[i + 2]))
            c = re.match(r"^([\d.,]+)([KM]?) ite(?:m|ns)$", text(lines[i + 3]))
            if c:
                out["items"] = int(round(float(c.group(1).replace(",", ".")) * COUNT[c.group(2)]))
        elif s == "AXRow [level=0]:":
            # Linha da lista: nome (texto ou botão "Outros itens") seguido do tamanho.
            texts = []
            for nxt in lines[i + 1:i + 8]:
                n = nxt.strip()
                if n.startswith("AXRow") or n.startswith("AXList"):
                    break
                if n.startswith("AXStaticText: ") or n.startswith("AXButton: Outros itens"):
                    texts.append(text(nxt))
            if len(texts) < 2:
                continue
            name, size = texts[-2], to_bytes(texts[-1])
            if name == "Outros itens":
                out["others"] = size
            elif name == "Espaço Purgável":
                out["purgeable"] = size
            else:
                out["children"].append([name, size])
    return usage, out


def convert(folder):
    volume, folders = None, {}
    for name in sorted(os.listdir(folder)):
        if not name.endswith(".txt"):
            continue
        with open(os.path.join(folder, name), encoding="utf-8") as f:
            usage, data = convert_folder(f.read().splitlines())
        volume = volume or usage
        folders[name[:-4]] = data
    return {"volume": volume, "folders": folders}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(convert(sys.argv[1]), f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
