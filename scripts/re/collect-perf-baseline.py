#!/usr/bin/env python3
"""Roda a análise do Desempenho no CleanMyMac e despeja Resultados e as três seções do Gerenciador.

Uso: python3 -I scripts/re/collect-perf-baseline.py
Saída: re-notes/ax/perf-baseline-<data>/{results,maintenance,login-items,background-items}.txt

Só analisa e navega: o dump-ax recusa executar, liberar, diminuir, reindexar, acelerar, reparar, desativar e remover.
"""
import os, re, sys, time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
apps = __import__("collect-apps-baseline")

SECTIONS = [("Tarefas de Manutenção", "maintenance"), ("Itens de Início", "login-items"),
            ("Itens em Segundo Plano", "background-items")]
SCAN_TIMEOUT = 300


def has_button(lines, title):
    """O botão existe, em qualquer estado ("Enabled | ", "Pressed | " ou sem estado)."""
    return any(re.fullmatch(r"AXButton: (?:\w+ \| )?" + re.escape(title), l.strip()) for l in (lines or []))


def main():
    if not os.access(apps.AX, os.X_OK):
        sys.exit("compile antes: swiftc -O scripts/re/dump-ax.swift -o re-notes/dump-ax")
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(apps.AX_DIR, "perf-baseline-" + datetime.now().strftime("%Y%m%d-%H%M"))
    os.makedirs(out_dir, exist_ok=True)

    apps.dump("b", "--press", "Desempenho")
    # Pode estar no Gerenciador (Voltar) ou em Resultados (Recomeçar pede confirmação num diálogo).
    if has_button(apps.dump("b"), "Voltar"):
        apps.dump("b", "--press", "Voltar")
    if has_button(apps.dump("b"), "Recomeçar"):
        apps.dump("b", "--press", "Recomeçar")
        time.sleep(1)
        if has_button(apps.dump("b"), "Cancelar"):
            apps.dump("b", "--press", "Recomeçar", "--last")
        time.sleep(1)
    apps.dump("b", "--press", "Analisar")
    deadline = time.time() + SCAN_TIMEOUT
    results = None
    while time.time() < deadline:
        time.sleep(3)
        lines = apps.dump("b")
        if has_button(lines, "Ver Todas as Tarefas"):
            results = lines
            break
    if results is None:
        sys.exit("a análise não terminou em %d s" % SCAN_TIMEOUT)
    apps.save(out_dir, "results", results)

    apps.dump("b", "--press", "Ver Todas as Tarefas")
    for title, name in SECTIONS:
        apps.dump("b", "--press", title)
        time.sleep(1)
        apps.save(out_dir, name, apps.dump("b"))
    print(out_dir)


if __name__ == "__main__":
    main()
