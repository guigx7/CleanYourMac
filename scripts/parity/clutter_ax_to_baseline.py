#!/usr/bin/env python3
"""Converte os dumps do Acúmulos do CleanMyMac em uma baseline JSON.

Uso: python3 -I scripts/parity/clutter_ax_to_baseline.py <pasta> <saída.json>
A pasta tem results.txt, manager.txt (Fundo do Baú), duplicatas.txt, imagens-similares.txt e downloads.txt.
"""
import json, os, re, sys, unicodedata

UNITS = {"bytes": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
MONTHS = {"jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6, "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11,
          "dez": 12}
GROUP_SIZE = "| Tamanho total dos itens no grupo"
ITEM_SIZE = "| Tamanho total ou contagem dos itens incluídos"
LAST_OPENED = "| A última vez que você abriu o arquivo."


def to_bytes(text):
    m = re.match(r"^\s*([\d.,]+)\s*(bytes|KB|MB|GB|TB)\s*$", text)
    if not m:
        return None
    return int(round(float(m.group(1).replace(".", "").replace(",", ".")) * UNITS[m.group(2)]))


def to_date(text):
    m = re.match(r"^(\d{1,2}) de (\w{3})\.? de (\d{4})$", text.strip())
    return f"{int(m.group(3)):04d}-{MONTHS[m.group(2)]:02d}-{int(m.group(1)):02d}" if m else None


def value(line):
    """Texto de um AXStaticText (antes do " | ", quando há descrição)."""
    s = line.strip()
    s = s.split(": ", 1)[1] if ": " in s else ""
    return s.split(" | ")[0]


def read(folder, name):
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        # A Acessibilidade devolve acentos decompostos e espaços não separáveis: normaliza.
        return unicodedata.normalize("NFC", f.read()).replace("\u00a0", " ").replace("\u202f", " ").splitlines()


def groups(lines):
    """Grupos (Duplicatas, Similares): nome/data, tamanho somado e contagem."""
    out = []
    for i, line in enumerate(lines):
        if GROUP_SIZE in line and i + 1 < len(lines) and "| O total de" in lines[i + 1]:
            out.append((value(lines[i - 1]), to_bytes(value(line)), int(value(lines[i + 1]))))
    return out


def rows(lines):
    """Linhas de arquivo: nome, pasta (caminho), última abertura e tamanho."""
    out, cur = [], None
    for i, line in enumerate(lines):
        s = line.strip()
        if s.startswith("AXCell: "):
            cur = {"name": s[len("AXCell: "):]}
            out.append(cur)
        elif cur is not None and s == "AXList: caminho":
            parts = []
            for nxt in lines[i + 1:i + 8]:
                if not nxt.strip().startswith("AXStaticText: ") or "|" in nxt:
                    break
                parts.append(value(nxt))
            cur["folder"] = "/".join(parts)
        elif cur is not None and LAST_OPENED in s:
            cur["lastOpened"] = to_date(value(s))
        elif cur is not None and ITEM_SIZE in s:
            cur["size"] = to_bytes(value(s))
    return out


def convert(folder):
    results = read(folder, "results.txt")
    total, tiles = None, []
    for i, line in enumerate(results):
        m = re.search(r"Você tem ([\d.]+) arquivos? para revisar", line)
        if m:
            total = int(m.group(1).replace(".", ""))
        s = line.strip()
        if s.startswith("AXStaticText: ") and re.search(r"Encontrad[oa]s?( em .+)?$", s) and "Revisar" not in s:
            tiles.append({"text": value(s), "detail": value(results[i + 1])})
    downloads = read(folder, "downloads.txt")
    dl_groups = {}
    for i, line in enumerate(downloads):
        if GROUP_SIZE in line:
            dl_groups[value(downloads[i - 1])] = to_bytes(value(line))
    return {
        "total": total,
        "tiles": tiles,
        "largeOld": rows(read(folder, "manager.txt")),
        "duplicates": [{"name": n, "size": s, "count": c} for n, s, c in groups(read(folder, "duplicatas.txt"))],
        "similar": [{"date": to_date(n), "size": s, "count": c} for n, s, c in groups(read(folder, "imagens-similares.txt"))],
        "downloads": {"groups": dl_groups,
                      "files": [{"name": r["name"], "size": r.get("size")} for r in rows(downloads)]},
    }


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(convert(sys.argv[1]), f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
