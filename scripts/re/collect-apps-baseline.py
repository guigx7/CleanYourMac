#!/usr/bin/env python3
"""Percorre o Gerenciador de Aplicativos do CleanMyMac (já aberto após uma análise) e despeja cada tela.

Uso: python3 -I scripts/re/collect-apps-baseline.py
Saída: re-notes/ax/apps-baseline-<data>/{uninstaller,filter-*,app-*,updater,leftovers-*}.txt

Só navega: o dump-ax recusa qualquer elemento que pareça desinstalar, remover, atualizar ou redefinir.
"""
import os, re, shutil, subprocess, sys, time
from datetime import datetime

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
AX = os.path.join(REPO, "re-notes", "dump-ax")
AX_DIR = os.path.join(REPO, "re-notes", "ax")
SHOW = "Mostre os itens incluídos"
HIDE = "Oculte os itens incluídos"
# Apps com árvore enorme (ex.: bibliotecas do GarageBand) travam a Acessibilidade: tempo-limite por tela.
TIMEOUT = 90
CMM = "/Applications/Setapp/CleanMyMac.app"
KIND_NAMES = {"Aplicativos", "Binários", "Contêiner", "Falhas", "Ícone do Dock", "Ajuda", "Instaladores",
              "Itens de Início", "Registros", "Outros", "Plug-ins", "Preferências", "Arquivos de Suporte",
              "Dados de Usuário"}
FILTERS = ["Todos os Aplicativos", "Não Usados", "Selecionados", "App Store", "Setapp", "Steam", "Battle.net",
           "Outro", "Apple", "Google", "JetBrains", "MacPaw", "Microsoft", "Adobe", "Outros", "Plug‑ins de Áudio"]


def dump(label, *press):
    """Roda o dump-ax (opcionalmente clicando antes) e devolve as linhas do arquivo gerado."""
    # Fora de foco, o CleanMyMac fecha a janela principal para a Acessibilidade: traz para frente antes.
    subprocess.run(["open", "-a", CMM], capture_output=True)
    try:
        out = subprocess.run([AX, label, *press], capture_output=True, text=True, timeout=TIMEOUT)
    except subprocess.TimeoutExpired:
        return None
    if out.returncode != 0:
        return None
    path = out.stdout.strip().split("→ ")[-1]
    with open(path, encoding="utf-8") as f:
        lines = f.read().splitlines()
    os.remove(path)
    return lines


def show_buttons(lines):
    """Para cada botão "Mostre…", na ordem: (célula, é linha de app?)."""
    result, cell, is_app = [], None, False
    for line in lines:
        s = line.strip()
        if s.startswith("AXCell: "):
            cell, is_app = s[len("AXCell: "):], False
        elif "O dia em que você abriu" in s:
            is_app = True
        elif s == "AXButton: " + SHOW:
            result.append((cell, is_app))
    return result


def save(out_dir, name, lines):
    safe = re.sub(r"[/:]", "_", name)
    with open(os.path.join(out_dir, safe + ".txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(lines or []))


def collect_app(out_dir, i, app):
    """Expande a linha do app e, dentro dela, só as linhas de tipo (não as subpastas)."""
    lines = dump("b", "--press", SHOW, "--index", str(i))
    for _ in range(20):
        buttons = show_buttons(lines or [])
        app_row = [k for k, (c, is_app) in enumerate(buttons) if is_app]
        nxt = next((k for k in app_row if k >= i), len(buttons))
        kinds = [k for k in range(i, nxt) if buttons[k][0] in KIND_NAMES]
        if lines is None or not kinds:
            break
        lines = dump("b", "--press", SHOW, "--index", str(kinds[0]))
    time.sleep(0.5)
    final = dump("b") if lines is not None else None
    save(out_dir, "app-" + app if final is not None else "timeout-" + app, final)
    dump("b", "--press", HIDE, "--index", "0")
    print("ok:" if final is not None else "tempo esgotado:", app, flush=True)


def main():
    if not os.access(AX, os.X_OK):
        sys.exit("compile antes: swiftc -O scripts/re/dump-ax.swift -o re-notes/dump-ax")
    # Uso: collect-apps-baseline.py [pasta existente] [app ...] — retoma uma coleta só com os apps pedidos.
    args = sys.argv[1:]
    out_dir = args.pop(0) if args and os.path.isdir(args[0]) else \
        os.path.join(AX_DIR, "apps-baseline-" + datetime.now().strftime("%Y%m%d-%H%M"))
    # --filter <rótulo>: aplica um filtro antes de montar a lista (ex.: apps da Apple).
    view = None
    if "--filter" in args:
        k = args.index("--filter")
        view = args[k + 1]
        del args[k:k + 2]
    only = set(args)
    os.makedirs(out_dir, exist_ok=True)

    dump("b", "--press", "Gerenciar Aplicativos")
    dump("b", "--press", "Desinstalador")
    while any(l.strip() == "AXButton: " + HIDE for l in (dump("b") or [])):
        dump("b", "--press", HIDE, "--index", "0")
    save(out_dir, "uninstaller", dump("b"))
    for f in FILTERS:
        lines = dump("b", "--press", f)
        if lines is not None:
            save(out_dir, "filter-" + f, lines)
    dump("b", "--press", view or "Todos os Aplicativos")

    # Cada app: expande a linha e os tipos dela, despeja, recolhe. Se o clique em "Todos" falhar, a lista
    # fica filtrada: os apps que faltarem são coletados pelos filtros de fornecedor.
    done = set()
    for view_name in [view or "Todos os Aplicativos", "Apple", "Google", "MacPaw", "Microsoft", "Outros"]:
        dump("b", "--press", view_name)
        base = show_buttons(dump("b") or [])
        apps = [c for c, is_app in base if is_app]
        for i, app in enumerate(apps):
            if app in done or (only and app not in only):
                continue
            collect_app(out_dir, i, app)
            done.add(app)
        if view:
            break

    save(out_dir, "updater", dump("b", "--press", "Atualizador"))
    save(out_dir, "leftovers", dump("b", "--press", "Sobras"))
    for g in ["Arquivos de Sobras", "Instaladores"]:
        lines = dump("b", "--press", g)
        for _ in range(20):
            if not show_buttons(lines or []):
                break
            lines = dump("b", "--press", SHOW, "--index", "0")
        save(out_dir, "leftovers-" + g, lines)
    print(out_dir)


if __name__ == "__main__":
    main()
