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
from title_enrichment import (  # noqa: E402
    build_championships,
    merge_titles,
    sort_titles_by_year,
)

_SUMMARY_RE = __import__("re").compile(
    r"^(Títulos em simples|Títulos em duplas|Títulos na carreira|Último resultado:)",
    __import__("re").I,
)


def _is_summary(line: str) -> bool:
    return bool(_SUMMARY_RE.match(line.strip()))


def _event_lines(titles: list[str]) -> list[str]:
    return [t for t in titles if not _is_summary(t)]


def _merge_with_existing(existing: list[str], fresh: list[str]) -> list[str]:
    fresh_events = _event_lines(fresh)
    existing_events = _event_lines(existing)
    if not fresh_events:
        return existing
    fresh_summary = [t for t in fresh if _is_summary(t)]
    existing_summary = [t for t in existing if _is_summary(t)]
    summary = fresh_summary or existing_summary
    merged = sort_titles_by_year(
        list(summary) + merge_titles(existing_events, fresh_events)
    )
    if len(_event_lines(merged)) < len(existing_events):
        return existing
    return merged


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
    restored_events = 0

    # Prefetch existing titles by ittf_id
    existing_rows = (
        client.table("athletes")
        .select("ittf_id,championships_won")
        .execute()
        .data
        or []
    )
    existing_by_ittf = {
        str(r.get("ittf_id") or ""): list(r.get("championships_won") or [])
        for r in existing_rows
        if r.get("ittf_id")
    }

    for sub_event in ("MS", "WS"):
        rows = collect_gender_rankings(all_rankings, sub_event)
        for index, row in enumerate(rows, start=1):
            name = row.get("PlayerName", "?")
            ittf_id = str(row.get("IttfId", "")).strip()
            print(f"[{index}/100] {name}")

            card = fetch_card(ittf_id) if ittf_id else {}
            fresh = build_championships(card, name)
            existing = existing_by_ittf.get(ittf_id, [])
            titles = _merge_with_existing(existing, fresh)

            before = len(_event_lines(existing))
            after = len(_event_lines(titles))
            if titles != existing:
                client.table("athletes").update({"championships_won": titles}).eq(
                    "ittf_id", ittf_id
                ).execute()
                updated += 1
                if after > before:
                    restored_events += after - before
                existing_by_ittf[ittf_id] = titles
                print(f"  -> {before} -> {after} event titles")
            else:
                print(f"  -> unchanged ({after} event titles)")
            time.sleep(0.15)

    print(
        f"Concluido: {updated} atletas atualizados; "
        f"+{restored_events} event titles liquidos."
    )


if __name__ == "__main__":
    main()
