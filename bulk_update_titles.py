#!/usr/bin/env python3
"""Gera SQL de atualização de títulos para execução via service role / MCP."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

from scraper import (  # noqa: E402
    PLAYER_CARD_URL,
    WTT_HEADERS,
    collect_gender_rankings,
    fetch_rankings,
)
from title_enrichment import build_championships  # noqa: E402


def fetch_card(ittf_id: str) -> dict:
    r = requests.get(f"{PLAYER_CARD_URL}{ittf_id}", headers=WTT_HEADERS, timeout=60)
    if r.status_code != 200:
        return {}
    details = r.json().get("details")
    if not details:
        return {}
    return json.loads(details)


def sql_escape(value: str) -> str:
    return value.replace("'", "''")


def to_pg_array(values: list[str]) -> str:
    escaped = [f"'{sql_escape(v)}'" for v in values]
    return "ARRAY[" + ", ".join(escaped) + "]::text[]"


def main() -> None:
    out_path = ROOT / "title_updates.sql"
    all_rankings = fetch_rankings()
    statements: list[str] = ["BEGIN;"]

    for sub_event in ("MS", "WS"):
        rows = collect_gender_rankings(all_rankings, sub_event)
        for row in rows:
            name = row.get("PlayerName", "?")
            ittf_id = str(row.get("IttfId", "")).strip()
            if not ittf_id:
                continue

            card = fetch_card(ittf_id)
            titles = build_championships(card, name)
            arr = to_pg_array(titles)
            statements.append(
                f"UPDATE athletes SET championships_won = {arr}, "
                f"updated_at = NOW() WHERE ittf_id = '{sql_escape(ittf_id)}';"
            )
            time.sleep(0.1)

    statements.append("COMMIT;")
    out_path.write_text("\n".join(statements), encoding="utf-8")
    print(f"Gerado {out_path} com {len(statements) - 2} updates.")


if __name__ == "__main__":
    main()
