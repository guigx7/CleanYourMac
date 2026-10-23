#!/usr/bin/env python3
"""Compara a baseline do Acúmulos do CleanMyMac com a nossa (`cym clutter --json`).

Uso: python3 -I scripts/parity/compare_clutter.py <baseline.json> <nosso.json> [divergências.json]

Regras (design v0.5):
- Fundo do Baú: mesmos nomes; tamanho dentro do arredondamento da tela mais 1%; data de abertura diferente é nota;
- Duplicatas: mesmo número de grupos e mesmos títulos; tamanho do grupo com a mesma tolerância;
- Downloads: mesmos apps com espaço (app só no CleanMyMac com 0 KB é nota); total por app com 5% (o CleanMyMac mostra alguns
  arquivos maiores que o disco); mesmos nomes de arquivo;
- cartões: mesmas categorias; contagem igual; espaço com a tolerância da categoria (Similares: nota);
- Similares e o total ("Você tem N arquivos"): só notas (dependem do hash e da fototeca).
Nomes comparados em NFC. Divergências conhecidas: {"largeOld"|"duplicates"|"downloads": {"nome": motivo}}.
Sai com 1 se houver falha.
"""
import json, re, sys, unicodedata

UNITS = {"KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12, "bytes": 1}


def nfc(s):
    return unicodedata.normalize("NFC", s or "")


def half_step(v):
    """Meia unidade do último algarismo que a tela mostra: uma casa decimal abaixo de 100 unidades, inteiro acima."""
    if not v:
        return 500
    for unit in (1e12, 1e9, 1e6, 1e3):
        if abs(v) >= unit:
            return (0.1 if abs(v) / unit < 100 else 1) * unit / 2
    return 0.5


def close(cmm, ours, extra=0.01):
    if cmm is None or ours is None:
        return cmm == ours
    return abs(cmm - ours) <= half_step(cmm) + extra * abs(cmm)


def parse_size(text):
    """Primeiro "15,9 MB" do texto, em bytes."""
    m = re.search(r"(\d+(?:[.,]\d+)?)\s*(KB|MB|GB|TB|bytes)", text or "")
    return None if not m else float(m.group(1).replace(",", ".")) * UNITS[m.group(2)]


def tile_info(tile):
    """Categoria, contagem e espaço de um cartão do CleanMyMac (texto da tela)."""
    text, detail = nfc(tile.get("text")), nfc(tile.get("detail"))
    if "Similares" in text or "Similar" in text:
        kind = "similar"
    elif "Duplicad" in text or "Duplicate" in text:
        kind = "duplicates"
    elif "Downloads" in text:
        kind = "downloads"
    else:
        kind = "largeOld"
    count = None
    m = re.match(r"(\d+)\s", text)
    if m and kind != "downloads":
        count = int(m.group(1))
    size = parse_size(text) if kind == "downloads" else parse_size(detail)
    return kind, count, size


def our_tile_kind(kind):
    for prefix in ("similar", "duplicates", "downloads", "largeOld"):
        if kind.startswith(prefix):
            return prefix
    return kind


def mb(v):
    return "?" if v is None else f"{v / 1e6:.1f} MB"


def compare(base, ours, known):
    failures, notes = [], []

    def miss(section, name, msg):
        allowed = known.get(section, {})
        (notes.append(f"{msg} (conhecida: {allowed[name]})") if name in allowed else failures.append(msg))

    # Fundo do Baú
    bl = {nfc(f["name"]): f for f in base.get("largeOld", [])}
    ol = {nfc(f["name"]): f for f in ours.get("largeOld", [])}
    for name in sorted(set(bl) | set(ol)):
        if name not in ol or name not in bl:
            miss("largeOld", name, f"Fundo do Baú: {name} {'só no CleanMyMac' if name in bl else 'só em nós'}")
            continue
        if not close(bl[name]["size"], ol[name]["size"]):
            failures.append(f"Fundo do Baú: {name}: CleanMyMac {mb(bl[name]['size'])}, nós {mb(ol[name]['size'])}")
        if bl[name].get("lastOpened") != ol[name].get("lastOpened"):
            notes.append(f"Fundo do Baú: {name}: aberto em {bl[name].get('lastOpened')} × {ol[name].get('lastOpened')}")

    # Duplicatas
    bd, od = base.get("duplicates", []), ours.get("duplicates", [])
    if len(bd) != len(od):
        failures.append(f"Duplicatas: {len(bd)} grupos no CleanMyMac, {len(od)} em nós")
    bt, ot = {}, {}
    for g in bd:
        bt.setdefault(nfc(g["name"]), []).append(g)
    for g in od:
        ot.setdefault(nfc(g["name"]), []).append(g)
    for name in sorted(set(bt) | set(ot)):
        b, o = bt.get(name, []), ot.get(name, [])
        if len(b) != len(o):
            miss("duplicates", name, f"Duplicatas: \"{name}\" {len(b)} grupo(s) no CleanMyMac, {len(o)} em nós")
            continue
        for gb_, go in zip(sorted(b, key=lambda g: g["size"]), sorted(o, key=lambda g: g["size"])):
            if not close(gb_["size"], go["size"]):
                failures.append(f"Duplicatas: \"{name}\": CleanMyMac {mb(gb_['size'])}, nós {mb(go['size'])}")
            if gb_.get("count") != go.get("count"):
                failures.append(f"Duplicatas: \"{name}\": {gb_.get('count')} cópias no CleanMyMac, {go.get('count')} em nós")

    # Downloads
    bg = base.get("downloads", {}).get("groups", {})
    og = ours.get("downloads", {}).get("groups", {})
    for app in sorted(set(bg) | set(og)):
        b, o = bg.get(app), og.get(app)
        if o is None and not b:
            notes.append(f"Downloads: {app} só no CleanMyMac, com 0 KB")
        elif b is None or o is None:
            failures.append(f"Downloads: {app} {'só no CleanMyMac' if o is None else 'só em nós'}")
        elif not close(b, o, 0.05):
            failures.append(f"Downloads: {app}: CleanMyMac {mb(b)}, nós {mb(o)}")
    bf = {nfc(f["name"]) for f in base.get("downloads", {}).get("files", [])}
    of = {nfc(f["name"]) for f in ours.get("downloads", {}).get("files", [])}
    for name in sorted(bf ^ of):
        miss("downloads", name, f"Downloads: {name} {'só no CleanMyMac' if name in bf else 'só em nós'}")

    # Cartões
    bk = {}
    for t in base.get("tiles", []):
        kind, count, size = tile_info(t)
        bk[kind] = (count, size)
    ok = {}
    for t in ours.get("tiles", []):
        ok[our_tile_kind(t["kind"])] = (t.get("count"), t.get("size"), t["kind"])
    for kind in sorted(set(bk) | set(ok)):
        if kind not in ok or kind not in bk:
            msg = f"Cartões: {kind} {'só no CleanMyMac' if kind in bk else 'só em nós'}"
            (notes if kind == "similar" else failures).append(msg)
            continue
        (bc, bs), (oc, os_, okind) = bk[kind], ok[kind]
        bucket = notes if kind == "similar" else failures
        if bc is not None and bc != oc:
            bucket.append(f"Cartões: {okind}: {bc} itens no CleanMyMac, {oc} em nós")
        if bs is not None and not close(bs, os_, 0.05 if kind == "downloads" else 0.01):
            bucket.append(f"Cartões: {okind}: CleanMyMac {mb(bs)}, nós {mb(os_)}")

    # Similares e total: notas
    bs_, os2 = base.get("similar", []), ours.get("similar", [])
    notes.append(f"Similares: {len(bs_)} grupos / {sum(g['count'] for g in bs_)} imagens no CleanMyMac, "
                 f"{len(os2)} grupos / {sum(g['count'] for g in os2)} imagens em nós")
    if base.get("total") != ours.get("total"):
        notes.append(f"Total: {base.get('total')} no CleanMyMac, {ours.get('total')} em nós")
    return failures, notes


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        base = json.load(f)
    with open(sys.argv[2], encoding="utf-8") as f:
        ours = json.load(f)
    known = {}
    if len(sys.argv) > 3:
        with open(sys.argv[3], encoding="utf-8") as f:
            known = json.load(f)
    failures, notes = compare(base, ours, known)
    for n in notes:
        print("nota:", n)
    for f in failures:
        print("FALHA:", f)
    print(f"{len(failures)} falha(s), {len(notes)} nota(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
