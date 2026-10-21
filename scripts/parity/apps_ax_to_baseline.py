#!/usr/bin/env python3
"""Converte os dumps de collect-apps-baseline.py em uma baseline JSON do módulo Aplicativos.

Uso: python3 -I scripts/parity/apps_ax_to_baseline.py <pasta apps-baseline-AAAAMMDD-HHMM> <saída.json>
"""
import json, os, re, sys
from datetime import datetime, timezone

UNITS = {"KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12}
MONTHS = {"jan": 1, "fev": 2, "mar": 3, "abr": 4, "mai": 5, "jun": 6,
          "jul": 7, "ago": 8, "set": 9, "out": 10, "nov": 11, "dez": 12}
KINDS = {"Aplicativos": "applications", "Binários": "binaries", "Contêiner": "container", "Falhas": "crashes",
         "Ícone do Dock": "dockIcon", "Ajuda": "help", "Instaladores": "installers", "Itens de Início": "loginItems",
         "Registros": "logs", "Outros": "other", "Plug-ins": "plugins", "Preferências": "preferences",
         "Arquivos de Suporte": "supportingFiles", "Dados de Usuário": "userData"}
# Rótulo do filtro → chave; "Outro"/"Outros" dependem da seção (Lojas/Fornecedores).
FILTERS = {"Todos os Aplicativos": "all", "Não Usados": "unused", "Suspeitos": "suspicious", "Selecionados": "selected",
           "App Store": "appStore", "Setapp": "setapp", "Steam": "steam", "Battle.net": "battleNet", "Outro": "storeOther",
           "Apple": "apple", "Google": "google", "JetBrains": "jetBrains", "MacPaw": "macPaw", "Microsoft": "microsoft",
           "Adobe": "adobe", "Outros": "vendorOther", "Plug‑ins de Áudio": "audioPlugins"}
SIZE_HINT = "Tamanho total ou contagem dos itens incluídos"
DATE_HINT = "O dia em que você abriu"


def to_bytes(text):
    m = re.match(r"^\s*([\d.,]+)\s*(KB|MB|GB|TB)\s*$", text)
    if not m:
        return None
    return int(round(float(m.group(1).replace(".", "").replace(",", ".")) * UNITS[m.group(2)]))


def to_date(text):
    m = re.match(r"^(\d{1,2}) de (\w{3})\.? de (\d{4})$", text.strip())
    return f"{int(m.group(3)):04d}-{MONTHS[m.group(2)]:02d}-{int(m.group(1)):02d}" if m else None


def text_of(line):
    return line.split(":", 1)[1].strip() if ":" in line else ""


def cells(lines):
    """Agrupa as linhas por AXCell: [{name, date, size, level}] (level = nível na árvore, se o dump tiver)."""
    out, cur, level = [], None, None
    for line in lines:
        s = line.strip()
        m = re.match(r"^AXRow \[level=(\d+)\]", s)
        if m:
            level = int(m.group(1))
        elif s.startswith("AXCell: "):
            cur = {"name": s[len("AXCell: "):], "date": None, "size": None, "level": level}
            out.append(cur)
        elif cur is not None and s.startswith("AXStaticText:"):
            value = text_of(s).split(" | ")
            if len(value) == 2 and value[1].startswith(DATE_HINT):
                cur["date"] = to_date(value[0])
            elif len(value) == 2 and value[1] == SIZE_HINT:
                cur["size"] = to_bytes(value[0])
    return out


def filters(lines):
    texts = [text_of(l) for l in lines if l.strip().startswith("AXStaticText:")]
    out = {}
    for label, count in zip(texts, texts[1:]):
        if label in FILTERS and count.isdigit() and FILTERS[label] not in out:
            out[FILTERS[label]] = int(count)
    return out


def related(lines, app):
    """Tipos e itens abaixo da linha do app, até a próxima linha de app."""
    all_cells = cells(lines)
    if any(c["level"] is not None for c in all_cells):
        # Com nível: 0 = app, 1 = tipo, 2 = item; níveis mais fundos (dentro de um contêiner) ficam de fora.
        out, kind, inside = {}, None, False
        for c in all_cells:
            if c["level"] == 0:
                if inside:
                    break
                inside = c["name"] == app
            elif inside and c["level"] == 1 and c["name"] in KINDS:
                kind = KINDS[c["name"]]
                out.setdefault(kind, [])
            elif inside and c["level"] == 2 and kind is not None:
                out[kind].append({"name": c["name"], "size": c["size"]})
        return out
    out, kind, inside = {}, None, False
    for c in all_cells:
        if c["date"] is not None:
            if inside:
                break
            inside = c["name"] == app
            continue
        if not inside:
            continue
        if c["name"] in KINDS and c["size"] is None:
            kind = KINDS[c["name"]]
            out.setdefault(kind, [])
        elif kind is not None:
            out[kind].append({"name": c["name"], "size": c["size"]})
    return out


def leftover_tree(lines):
    """Sobras: nível 0 = app sumido, 1 = tipo, 2 = item do tipo (níveis mais fundos ficam de fora)."""
    out, kind = [], None
    for c in cells(lines):
        if c["level"] == 0 or c["level"] is None:
            out.append({"name": c["name"], "size": c["size"], "related": {}})
            kind = None
        elif c["level"] == 1 and out and c["name"] in KINDS:
            kind = KINDS[c["name"]]
            out[-1]["related"].setdefault(kind, [])
        elif c["level"] == 2 and out and kind is not None:
            out[-1]["related"][kind].append({"name": c["name"], "size": c["size"]})
    return out


def read(folder, name):
    path = os.path.join(folder, name)
    if not os.path.exists(path):
        return []
    with open(path, encoding="utf-8") as f:
        return f.read().splitlines()


def main():
    folder, output = sys.argv[1], sys.argv[2]
    # A vista "Todos os Aplicativos" é a lista completa; uninstaller.txt pode estar com um filtro aplicado.
    uninstaller = read(folder, "filter-Todos os Aplicativos.txt") or read(folder, "uninstaller.txt")
    apps = []
    for c in cells(uninstaller):
        if c["date"] is None:
            continue
        detail = read(folder, "app-" + re.sub(r"[/:]", "_", c["name"]) + ".txt")
        apps.append({"name": c["name"], "lastOpened": c["date"], "size": c["size"],
                     "related": related(detail, c["name"]) if detail else {}})
    updates = []
    for line in read(folder, "updater.txt"):
        m = re.match(r"^\s*AXStaticText: Versão (\S+) \| ", line)
        if m and updates is not None:
            updates[-1]["installed"] = m.group(1)
        m = re.match(r"^\s*AXCell: (.+)$", line)
        if m:
            updates.append({"name": m.group(1), "installed": None})
    leftovers = {}
    leftovers["leftoverFiles"] = leftover_tree(read(folder, "leftovers-Arquivos de Sobras.txt"))
    leftovers["installers"] = [{"name": c["name"], "size": c["size"]}
                               for c in cells(read(folder, "leftovers-Instaladores.txt"))]
    baseline = {
        "cmmVersion": "5.7.2",
        "capturedAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "apps": apps,
        "filters": filters(uninstaller),
        "updates": updates,
        "leftovers": leftovers,
    }
    with open(output, "w", encoding="utf-8") as f:
        json.dump(baseline, f, ensure_ascii=False, indent=2)


if __name__ == "__main__":
    main()
