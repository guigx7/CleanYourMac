#!/usr/bin/env python3
"""Compara a baseline do módulo Desempenho do CleanMyMac com a saída de `cym performance --json`.

Uso: python3 -I scripts/parity/compare_perf.py <baseline.json> <cym.json> [divergências.json]

Regras (design v0.3):
- exatos: tarefas aplicáveis (títulos pt-BR da baseline → ids), itens de início e em segundo plano (repetidos
  comparados como listas) e as contagens dos cartões;
- o espaço purgável muda entre duas análises: diferença é nota;
- o que estiver em divergências.json (por seção) vira nota, com o motivo.
Sai com 1 se houver falha.
"""
import json, sys
from collections import Counter

TITLES = {"Acelerar o Mail": "speedUpMail", "Esvaziar Cache do DNS": "flushDNS",
          "Liberar Espaço Purgável": "freeUpPurgeable", "Reindexar o Spotlight": "reindexSpotlight",
          "Reparar Permissões do Disco": "repairPermissions", "Liberar RAM": "freeUpRAM",
          "Executar Scripts Periódicos": "periodicScripts", "Diminuir Capturas do Time Machine": "thinSnapshots"}


def diff_lists(section, base, ours, known, failures, notes):
    """Diferenças de multiconjunto; as listadas em `known[section]` viram notas."""
    allowed = known.get(section, {})
    b, o = Counter(base), Counter(ours)
    for name in sorted(set(b) | set(o)):
        if b[name] == o[name]:
            continue
        msg = f"{section}: {name} — CleanMyMac {b[name]}, nós {o[name]}"
        if name in allowed:
            notes.append(f"{msg} (conhecida: {allowed[name]})")
        else:
            failures.append(msg)


def compare(base, ours, known):
    failures, notes = [], []
    tasks = [TITLES.get(t, t) for t in base.get("tasks", [])]
    diff_lists("tasks", tasks, ours.get("tasks", []), known, failures, notes)
    diff_lists("loginItems", base.get("loginItems", []), ours.get("loginItems", []), known, failures, notes)
    diff_lists("backgroundItems", base.get("backgroundItems", []), ours.get("backgroundItems", []), known, failures, notes)
    bp, op = base.get("purgeable"), ours.get("purgeable")
    if (bp is None) != (op is None):
        failures.append(f"purgeable: CleanMyMac {bp}, nós {op}")
    elif bp != op:
        notes.append(f"purgeable: CleanMyMac {bp / 1e9:.1f} GB, nós {op / 1e9:.1f} GB (muda entre análises)")
    allowed = known.get("tiles", {})
    for key in sorted(set(base.get("tiles", {})) | set(ours.get("tiles", {}))):
        b, o = base.get("tiles", {}).get(key), ours.get("tiles", {}).get(key)
        if b != o:
            msg = f"tiles.{key}: CleanMyMac {b}, nós {o}"
            (notes.append(f"{msg} (conhecida: {allowed[key]})") if key in allowed else failures.append(msg))
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
