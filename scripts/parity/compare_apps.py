#!/usr/bin/env python3
"""Compara a baseline do módulo Aplicativos do CleanMyMac com a saída de `cym apps --json`.

Uso: python3 -I scripts/parity/compare_apps.py <baseline.json> <cym.json> [divergências.json]

Regras (design v0.2):
- exatos: lista de apps, contagens dos filtros, atualizações de apps (sem as do macOS), sobras e instaladores (por nome);
- arquivos relacionados: os nossos são um subconjunto dos dele (item a mais = falha; a menos = divergência listada);
- tamanhos de itens casados: tolerância de 1% ou 1 MB, mais o arredondamento da tela do CleanMyMac
  ("1,5 GB" = 1,45–1,55 GB); itens com o mesmo nome (em pastas diferentes) são comparados como listas;
- o tamanho do bundle (binaries) é nota, não falha: o CleanMyMac usa o tamanho do Spotlight, que pode estar velho;
- o próprio CleanYourMac muda durante o teste: as diferenças dele são notas.
Sai com 1 se houver falha.
"""
import json, sys

MB = 1_000_000


def rounding(n):
    """Meia unidade do último dígito mostrado pelo CleanMyMac (3 algarismos, unidades decimais)."""
    for unit in (1e12, 1e9, 1e6, 1e3):
        if n >= unit:
            value = n / unit
            step = 0.1 if value < 100 else 1
            return step * unit / 2
    return 0


def close(a, b):
    if a is None or b is None:
        return True
    return abs(a - b) <= max(MB, 0.01 * max(a, b), rounding(a))


def multiset(items):
    out = {}
    for i in items:
        out.setdefault(i["name"], []).append(i.get("size"))
    return {k: sorted(v, key=lambda x: x or 0) for k, v in out.items()}


def human(n):
    return "?" if n is None else f"{n / MB:.1f} MB"


def main():
    with open(sys.argv[1], encoding="utf-8") as f:
        base = json.load(f)
    with open(sys.argv[2], encoding="utf-8") as f:
        ours = json.load(f)
    failures, notes = [], []
    aliases, volatile = {}, set()
    if len(sys.argv) > 3:
        with open(sys.argv[3], encoding="utf-8") as f:
            known = json.load(f)
        aliases = known.get("leftoverNames", {})
        volatile = set(known.get("volatile", []))

    base_apps = {a["name"]: a for a in base.get("apps", [])}
    our_apps = {a["name"]: a for a in ours.get("apps", [])}
    if set(base_apps) != set(our_apps):
        failures.append(f"apps: só na baseline {sorted(set(base_apps) - set(our_apps))}, só no cym {sorted(set(our_apps) - set(base_apps))}")

    bf, of = base.get("filters", {}), ours.get("filters", {})
    for key in sorted(set(bf) | set(of)):
        if bf.get(key) != of.get(key):
            failures.append(f"filtro {key}: baseline {bf.get(key)} × cym {of.get(key)}")

    bu = {u["name"] for u in base.get("updates", [])}
    ou = {u["name"] for u in ours.get("updates", []) if u.get("source") != "macOS"}
    if bu != ou:
        failures.append(f"atualizações: baseline {sorted(bu)} × cym {sorted(ou)}")
    extra_system = [u["name"] for u in ours.get("updates", []) if u.get("source") == "macOS"]
    if extra_system:
        notes.append(f"atualizações do macOS só no cym (divergência documentada): {extra_system}")

    for key, label in [("leftoverFiles", "sobras"), ("installers", "instaladores")]:
        b = {aliases.get(i["name"], i["name"]): i.get("size") for i in base.get("leftovers", {}).get(key, [])}
        o = {i["name"]: i.get("size") for i in ours.get("leftovers", {}).get(key, [])}
        if set(b) != set(o):
            failures.append(f"{label}: só na baseline {sorted(set(b) - set(o))}, só no cym {sorted(set(o) - set(b))}")
        for name in set(b) & set(o):
            if not close(b[name], o[name]):
                failures.append(f"{label} {name}: {human(b[name])} × {human(o[name])}")

    for name in sorted(set(base_apps) & set(our_apps)):
        b_rel, o_rel = base_apps[name].get("related", {}), our_apps[name].get("related", {})
        if not b_rel:
            continue  # sem detalhe na baseline (ex.: o próprio CleanMyMac)
        soft = name == "CleanYourMac.app"
        for kind in sorted(set(b_rel) | set(o_rel)):
            b_items, o_items = multiset(b_rel.get(kind, [])), multiset(o_rel.get(kind, []))
            extra = sorted(set(o_items) - set(b_items))
            missing = sorted(set(b_items) - set(o_items))
            if extra:
                (notes if soft else failures).append(f"{name} {kind}: itens a mais no cym {extra}")
            if missing:
                notes.append(f"{name} {kind}: só na baseline (divergência) {missing}")
            for item in set(b_items) & set(o_items):
                for bsz, osz in zip(b_items[item], o_items[item]):
                    if not close(bsz, osz):
                        line = f"{name} {kind} {item}: {human(bsz)} × {human(osz)}"
                        relaxed = soft or kind == "binaries" or f"{name}/{kind}/{item}" in volatile
                        (notes if relaxed else failures).append(line)
        bs, os_ = base_apps[name].get("size"), our_apps[name].get("size")
        if not close(bs, os_):
            notes.append(f"{name}: tamanho da linha {human(bs)} × {human(os_)}")

    for line in failures:
        print("FALHA  " + line)
    for line in notes:
        print("nota   " + line)
    print(f"{len(failures)} falha(s), {len(notes)} nota(s)")
    sys.exit(1 if failures else 0)


if __name__ == "__main__":
    main()
