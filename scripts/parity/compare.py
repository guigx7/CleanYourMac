#!/usr/bin/env python3
"""Compara a análise do CleanMyMac (baseline) com a do cym.

Uso: python3 -I scripts/parity/compare.py <baseline.json> <cym.json>
Sai com 1 se algum grupo da baseline passar da tolerância: max(2%, 5 MB).
"""
import json, sys

TOL_PCT = 0.02
TOL_ABS = 5_000_000


def fmt(n):
    for unit, size in (("GB", 1e9), ("MB", 1e6), ("KB", 1e3)):
        if abs(n) >= size:
            return f"{n / size:.1f} {unit}"
    return f"{n} B"


def main(base_path, ours_path):
    base = json.load(open(base_path))["groups"]
    ours = json.load(open(ours_path))["groups"]
    failed = []
    print(f"{'grupo':<20} {'CMM':>10} {'cym':>10} {'dif':>8}  status")
    for group in sorted(set(base) | set(ours)):
        b = base.get(group, {"totalBytes": 0, "items": []})
        o = ours.get(group, {"totalBytes": 0, "items": []})
        diff = o["totalBytes"] - b["totalBytes"]
        pct = diff / b["totalBytes"] if b["totalBytes"] else (0 if diff == 0 else 1)
        ok = abs(diff) <= max(TOL_PCT * b["totalBytes"], TOL_ABS)
        if group not in base:
            status = "extra (sem baseline)"
        else:
            status = "ok" if ok else "FORA"
            if not ok:
                failed.append(group)
        print(f"{group:<20} {fmt(b['totalBytes']):>10} {fmt(o['totalBytes']):>10} {pct:>+7.1%}  {status}")
        b_names = {i["name"] for i in b["items"]}
        o_names = {i["name"] for i in o["items"]}
        only_b, only_o = sorted(b_names - o_names), sorted(o_names - b_names)
        if only_b:
            print(f"    só CMM: {', '.join(only_b[:15])}{' …' if len(only_b) > 15 else ''}")
        if only_o:
            print(f"    só cym: {', '.join(only_o[:15])}{' …' if len(only_o) > 15 else ''}")
        b_rec = {i["name"] for i in b["items"] if i.get("recommended")}
        o_rec = {i["name"] for i in o["items"] if i.get("recommended")}
        if group in base and b_rec != o_rec:
            print(f"    recomendados diferem: CMM={len(b_rec)} cym={len(o_rec)}")
    if failed:
        print(f"\nfora da tolerância: {', '.join(failed)}")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1], sys.argv[2]))
