#!/usr/bin/env python3
"""Roda a análise do disco na Lupa de Espaço do CleanMyMac e despeja a raiz, /Users e a pasta pessoal.

Uso: python3 -I scripts/re/collect-spacelens-baseline.py
Saída: re-notes/ax/spacelens-<data>/{root,users,home}.txt

Só analisa e navega (clique duplo no nome entra na pasta); o dump-ax recusa remover e afins.
"""
import getpass, os, re, sys, time
from datetime import datetime

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
apps = __import__("collect-apps-baseline")
SCAN_TIMEOUT = 900


def has_button(lines, title):
    return any(re.fullmatch(r"AXButton: (?:\w+ \| )?" + re.escape(title), l.strip()) for l in (lines or []))


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else \
        os.path.join(apps.AX_DIR, "spacelens-" + datetime.now().strftime("%Y%m%d-%H%M"))
    os.makedirs(out_dir, exist_ok=True)
    apps.dump("b", "--press", "Lupa de Espaço", "--last")
    time.sleep(1)
    if has_button(apps.dump("b"), "Recomeçar"):
        apps.dump("b", "--press", "Recomeçar")
        time.sleep(1)
        if has_button(apps.dump("b"), "Cancelar"):
            apps.dump("b", "--press", "Recomeçar", "--last")
        time.sleep(1)
    apps.dump("b", "--press", "Analisar")
    deadline = time.time() + SCAN_TIMEOUT
    root = None
    while time.time() < deadline:
        time.sleep(5)
        lines = apps.dump("b") or []
        if any(l.strip().endswith(" usados") for l in lines) and not any("Visualizando" in l for l in lines):
            root = lines
            break
    if root is None:
        sys.exit("a análise não terminou")
    apps.save(out_dir, "root", root)
    for target, name in [("Users", "users"), (getpass.getuser(), "home")]:
        apps.dump("b", "--press", target, "--double")
        time.sleep(3)
        apps.save(out_dir, name, apps.dump("b"))
    print(out_dir)


if __name__ == "__main__":
    main()
