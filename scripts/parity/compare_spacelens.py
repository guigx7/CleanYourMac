#!/usr/bin/env python3
"""Compara a baseline da Lupa de Espaço do CleanMyMac com a nossa (`CYM_LENS_PARITY` do app ou `cym spacelens --json`).

Uso: python3 -I scripts/parity/compare_spacelens.py <baseline.json> <nosso.json> [divergências.json]

Regras (design v0.4):
- tamanhos: dentro do arredondamento da tela do CleanMyMac (uma casa decimal abaixo de 100 unidades) mais 1% (o disco muda entre as análises);
- contagem de itens ("3M itens"): meia unidade do que a tela mostra, mais 5%;
- filhos visíveis: mesmos nomes (item a mais ou a menos = falha, salvo em divergências "children": {"pasta/nome": motivo});
  ordem diferente é nota;
- "Outros itens" e o purgável: tamanho com a mesma tolerância (o purgável muda entre análises: nota).
Sai com 1 se houver falha.
"""
import json, math, sys


def half_step(v):
    """Meia unidade do último algarismo que a tela mostra: uma casa decimal abaixo de 100 unidades, inteiro acima."""
    if not v:
        return 50_000
    for unit in (1e12, 1e9, 1e6, 1e3):
        if abs(v) >= unit:
            return (0.1 if abs(v) / unit < 100 else 1) * unit / 2
    return 500


def close(cmm, ours, extra=0.01):
    if cmm is None or ours is None:
        return cmm == ours
    return abs(cmm - ours) <= half_step(cmm) + extra * abs(cmm) + 1_000_000


def count_close(cmm, ours):
    if cmm is None or ours is None:
        return True
    step = 10 ** math.floor(math.log10(cmm)) if cmm >= 1000 else 1
    return abs(cmm - ours) <= step / 2 + 0.05 * cmm


def gb(v):
    return "?" if v is None else f"{v / 1e9:.2f} GB"


def compare(base, ours, known):
    failures, notes = [], []
    allowed = known.get("children", {})
    for key in ("used", "capacity"):
        b, o = base.get("volume", {}).get(key), ours.get("volume", {}).get(key)
        if not close(b, o, 0):
            failures.append(f"volume.{key}: CleanMyMac {gb(b)}, nós {gb(o)}")
    for name, bf in base.get("folders", {}).items():
        of = ours.get("folders", {}).get(name)
        if of is None:
            failures.append(f"{name}: pasta ausente na nossa análise")
            continue
        if not close(bf.get("size"), of.get("size")):
            failures.append(f"{name}.size: CleanMyMac {gb(bf.get('size'))}, nós {gb(of.get('size'))}")
        if not count_close(bf.get("items"), of.get("items")):
            failures.append(f"{name}.items: CleanMyMac {bf.get('items')}, nós {of.get('items')}")
        bc = {n: s for n, s in bf.get("children", [])}
        oc = {n: s for n, s in of.get("children", [])}
        for child in sorted(set(bc) | set(oc)):
            path = f"{name}/{child}"
            if child not in oc or child not in bc:
                msg = f"{path}: {'só no CleanMyMac' if child in bc else 'só em nós'}"
                (notes.append(f"{msg} (conhecida: {allowed[path]})") if path in allowed else failures.append(msg))
            elif not close(bc[child], oc[child]):
                failures.append(f"{path}: CleanMyMac {gb(bc[child])}, nós {gb(oc[child])}")
        border = [n for n, _ in bf.get("children", []) if n in oc]
        oorder = [n for n, _ in of.get("children", []) if n in bc]
        if border != oorder:
            notes.append(f"{name}: ordem diferente ({border} × {oorder})")
        if bf.get("others") is not None or of.get("others") is not None:
            if not close(bf.get("others") or 0, of.get("others") or 0, 0.05):
                failures.append(f"{name}.others: CleanMyMac {gb(bf.get('others'))}, nós {gb(of.get('others'))}")
        if bf.get("purgeable") != of.get("purgeable"):
            notes.append(f"{name}.purgeable: CleanMyMac {gb(bf.get('purgeable'))}, nós {gb(of.get('purgeable'))} (muda entre análises)")
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
