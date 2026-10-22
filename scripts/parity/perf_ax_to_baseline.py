#!/usr/bin/env python3
"""Converte os dumps de collect-perf-baseline.py em uma baseline JSON do módulo Desempenho.

Uso: python3 -I scripts/parity/perf_ax_to_baseline.py <pasta perf-baseline-AAAAMMDD-HHMM> <saída.json>
A pasta tem results.txt, maintenance.txt, login-items.txt e background-items.txt.
"""
import json, os, re, sys

UNITS = {"KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
# Frases dos cartões de Resultados → chave (o número vem antes ou depois de "Tem").
TILES = [(re.compile(r"^Você Tem (\d+) Ite(?:m|ns) de Início$"), "loginItems"),
         (re.compile(r"^(\d+) Tarefas? de Manutenção Recomendadas?$"), "maintenance"),
         (re.compile(r"^(\d+) Ite(?:m|ns) em Segundo Plano Encontrados?$"), "backgroundItems")]


def to_bytes(text):
    m = re.match(r"^\s*([\d.,]+)\s*(KB|MB|GB|TB)\s*$", text)
    if not m:
        return None
    return int(round(float(m.group(1).replace(".", "").replace(",", ".")) * UNITS[m.group(2)]))


def read(folder, name):
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def cells(lines):
    """Nomes das linhas da lista (AXCell), na ordem da tela."""
    return [l.strip()[len("AXCell: "):] for l in lines if l.strip().startswith("AXCell: ")]


def purgeable(lines):
    """O "Até 3,8 GB" logo abaixo de Liberar Espaço Purgável."""
    for l in lines:
        s = l.strip()
        if s.startswith("AXStaticText: Até "):
            return to_bytes(s[len("AXStaticText: Até "):])
    return None


def tiles(lines):
    out = {}
    for l in lines:
        s = l.strip()
        if not s.startswith("AXStaticText: "):
            continue
        text = s[len("AXStaticText: "):]
        for rx, key in TILES:
            m = rx.match(text)
            if m:
                out[key] = int(m.group(1))
    return out


def convert(folder):
    maintenance = read(folder, "maintenance.txt")
    return {"tasks": cells(maintenance),
            "purgeable": purgeable(maintenance),
            "loginItems": cells(read(folder, "login-items.txt")),
            "backgroundItems": cells(read(folder, "background-items.txt")),
            "tiles": tiles(read(folder, "results.txt"))}


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    with open(sys.argv[2], "w", encoding="utf-8") as f:
        json.dump(convert(sys.argv[1]), f, ensure_ascii=False, indent=2)
        f.write("\n")


if __name__ == "__main__":
    main()
