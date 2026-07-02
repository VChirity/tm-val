#!/usr/bin/env python3
"""Re-sincroniza apenas títulos (WTT card + Wikipedia) dos 200 atletas."""

from __future__ import annotations

import json
import os
import sys
import time
from pathlib import Path

import requests
from dotenv import load_dotenv
from supabase import create_client

ROOT = Path(__file__).resolve().parent
load_dotenv(ROOT / ".env")

from scraper import (  # noqa: E402
    PLAYER_CARD_URL,
    TTU_PLAYERS_URL,
    WTT_HEADERS,
    collect_gender_rankings,
    fetch_rankings,
)
from title_enrichment import build_championships  # noqa: E402


def fetch_card(ittf_id: str) -> dict:
    for attempt in range(3):
        try:
            r = requests.get(
                f"{PLAYER_CARD_URL}{ittf_id}", headers=WTT_HEADERS, timeout=30
            )
            if r.status_code != 200:
                return {}
            details = r.json().get("details")
            if not details:
                return {}
            return json.loads(details)
        except requests.RequestException:
            time.sleep(1.5 * (attempt + 1))
    return {}


def main() -> None:
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip() or os.getenv(
        "SUPABASE_ANON_KEY", ""
    ).strip()
    if not url or not key:
        print("Configure SUPABASE_URL e SUPABASE_SERVICE_KEY no .env")
        sys.exit(1)

    client = create_client(url, key)
    all_rankings = fetch_rankings()
    updated = 0

    for sub_event in ("MS", "WS"):
        rows = collect_gender_rankings(all_rankings, sub_event)
        for index, row in enumerate(rows, start=1):
            name = row.get("PlayerName", "?")
            ittf_id = str(row.get("IttfId", "")).strip()
            gender = "male" if sub_event == "MS" else "female"
            print(f"[{index}/100] {name}")

            card = fetch_card(ittf_id) if ittf_id else {}
            titles = build_championships(card, name)

            client.table("athletes").update({"championships_won": titles}).eq(
                "ittf_id", ittf_id
            ).execute()
            updated += 1
            time.sleep(0.15)

    print(f"Concluído: {updated} atletas com títulos enriquecidos.")


if __name__ == "__main__":
    main()
