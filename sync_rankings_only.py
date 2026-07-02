#!/usr/bin/env python3
"""Atualiza ranking e pontuacao a partir do JSON da WTT (rapido)."""

from __future__ import annotations

import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path

import requests
from dotenv import load_dotenv
from supabase import create_client

ROOT = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT))

from scraper import (  # noqa: E402
    APP_EMAIL,
    APP_PASSWORD,
    GENDER_MAP,
    RANKING_URL,
    WTT_HEADERS,
    collect_gender_rankings,
    fetch_rankings,
    get_client,
    parse_int,
    upsert_athletes,
)


def build_ranking_record(row: dict) -> dict:
    sub_event = row.get("SubEventCode", "")
    gender = GENDER_MAP.get(sub_event)
    if gender is None:
        raise ValueError(f"SubEventCode desconhecido: {sub_event}")

    return {
        "name": row.get("PlayerName"),
        "gender": gender,
        "ranking": parse_int(row.get("CurrentRank") or row.get("RankingPosition")),
        "ranking_points": parse_int(
            row.get("RankingPointsYTD") or row.get("RankingPointsCareer")
        ),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def main() -> None:
    client = get_client()
    all_rankings = fetch_rankings()
    athletes: list[dict] = []

    for sub_event in ("MS", "WS"):
        for row in collect_gender_rankings(all_rankings, sub_event):
            athletes.append(build_ranking_record(row))

    upsert_athletes(client, athletes)
    print(f"Ranking/pontuacao atualizados para {len(athletes)} atletas.")


if __name__ == "__main__":
    main()
