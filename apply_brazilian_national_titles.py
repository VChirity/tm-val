#!/usr/bin/env python3
"""Mescla títulos nacionais BR curados em championships_won dos atletas brasileiros."""
from __future__ import annotations

import json
from pathlib import Path

from title_enrichment import merge_titles, sort_titles_by_year

ROOT = Path(__file__).resolve().parent
SEED = ROOT / "data" / "brazilian_national_titles.json"


def esc(s: str) -> str:
    return s.replace("'", "''")


def main() -> None:
    seed = json.loads(SEED.read_text(encoding="utf-8"))
    dump_path = ROOT / "_athletes_titles_dump.json"
    if not dump_path.exists():
        raise SystemExit("Falta _athletes_titles_dump.json — exporte athletes antes.")

    rows = json.loads(dump_path.read_text(encoding="utf-8"))
    by_ittf = {str(r.get("ittf_id")): r for r in rows if r.get("ittf_id")}

    stmts: list[str] = []
    report = []
    for ittf_id, payload in seed["by_ittf_id"].items():
        row = by_ittf.get(ittf_id)
        if not row:
            report.append({"ittf_id": ittf_id, "status": "missing_athlete"})
            continue
        existing = row.get("championships_won") or []
        merged = sort_titles_by_year(merge_titles(existing, payload["titles"]))
        report.append(
            {
                "ittf_id": ittf_id,
                "name": row.get("name"),
                "before": len(existing),
                "after": len(merged),
                "added": [t for t in payload["titles"] if t in merged],
            }
        )
        arr = ",".join("'" + esc(t) + "'" for t in merged)
        stmts.append(
            "UPDATE athletes SET championships_won = ARRAY["
            + arr
            + "]::text[], country_code = COALESCE(country_code, 'BRA'), "
            "updated_at = NOW() WHERE ittf_id = '"
            + esc(ittf_id)
            + "';"
        )

    # Garante country_code BRA nos listados no seed mesmo sem título novo
    for ittf_id in seed["by_ittf_id"]:
        stmts.append(
            "UPDATE athletes SET country_code = 'BRA', updated_at = NOW() "
            "WHERE ittf_id = '" + esc(ittf_id) + "' AND (country_code IS NULL OR country_code = '');"
        )

    out = ROOT / "_apply_br_national.sql"
    out.write_text("\n".join(stmts), encoding="utf-8")
    (ROOT / "_apply_br_national_report.json").write_text(
        json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    print("stmts", len(stmts), "report", len(report), "->", out)


if __name__ == "__main__":
    main()
