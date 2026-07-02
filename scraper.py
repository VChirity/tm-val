#!/usr/bin/env python3
"""Coleta Top 100 masculino/feminino da WTT e faz upsert no Supabase."""

from __future__ import annotations

import json
import os
import sys
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import requests
from dotenv import load_dotenv
from supabase import Client, create_client

ROOT_DIR = Path(__file__).resolve().parent
ENV_PATH = ROOT_DIR / ".env"

WTT_HEADERS = {
    "Accept": "application/json, text/plain, */*",
    "Referer": "https://www.worldtabletennis.com/",
    "Origin": "https://www.worldtabletennis.com",
    "User-Agent": (
        "Mozilla/5.0 (Windows NT 10.0; Win64; x64) "
        "AppleWebKit/537.36 (KHTML, like Gecko) "
        "Chrome/120.0.0.0 Safari/537.36"
    ),
    "ApiKey": "2bf8b222-532c-4c60-8ebe-eb6fdfebe84a",
}

RANKING_URL = (
    "https://wtt-web-frontdoor-withoutcache-cqakg0andqf5hchn.a01.azurefd.net/ranking/"
)
TTU_PLAYERS_URL = (
    "https://wtt-ttu-connect-frontdoor-g6gwg6e2bgc6gdfm.a01.azurefd.net/Players/GetPlayers"
)
PLAYER_CARD_URL = (
    "https://wtt-website-api-prod-3-frontdoor-bddnb2haduafdze9.a01.azurefd.net/api/cms/PlayerCard/"
)

GENDER_MAP = {
    "MS": "male",
    "WS": "female",
}


APP_EMAIL = "victorchirity@colegioequacao.com"
APP_PASSWORD = "sushi123"


def load_config() -> tuple[str, str]:
    if not ENV_PATH.exists():
        print(
            f"Arquivo .env não encontrado. Copie .env.example para .env "
            f"e preencha SUPABASE_URL e SUPABASE_SERVICE_KEY."
        )
        sys.exit(1)

    load_dotenv(ENV_PATH)
    url = os.getenv("SUPABASE_URL", "").strip()
    key = os.getenv("SUPABASE_SERVICE_KEY", "").strip() or os.getenv(
        "SUPABASE_ANON_KEY", ""
    ).strip()

    if not url or not key:
        print("Erro: defina SUPABASE_URL e SUPABASE_SERVICE_KEY (ou SUPABASE_ANON_KEY) no .env")
        sys.exit(1)

    return url, key


def normalize_photo_url(url: str | None) -> str | None:
    if not url or "dummy" in url.lower():
        return None

    return (
        url.replace(
            "https://wttsimfiles.blob.core.windows.net",
            "https://photofiles.worldtabletennis.com",
        )
        .replace(
            "https://wttnewtest.blob.core.windows.net",
            "https://photofiles.worldtabletennis.com",
        )
        .strip()
        or None
    )


def parse_int(value: Any) -> int | None:
    if value is None or value == "":
        return None
    try:
        return int(float(str(value)))
    except (TypeError, ValueError):
        return None


def parse_float(value: Any) -> float | None:
    if value is None or value == "":
        return None
    try:
        return float(str(value))
    except (TypeError, ValueError):
        return None


def fetch_rankings() -> list[dict[str, Any]]:
    url = f"{RANKING_URL}SEN_SINGLES.json?q={int(time.time() * 1000)}"
    response = requests.get(url, headers=WTT_HEADERS, timeout=60)
    response.raise_for_status()
    payload = response.json()
    return payload.get("Result", [])


def fetch_player_profile(ittf_id: str) -> dict[str, Any]:
    params = {"IttfId": ittf_id, "q": int(time.time())}
    response = requests.get(
        TTU_PLAYERS_URL, headers=WTT_HEADERS, params=params, timeout=60
    )
    response.raise_for_status()
    result = response.json().get("Result") or []
    return result[0] if result else {}


def fetch_player_card(ittf_id: str) -> dict[str, Any]:
    response = requests.get(
        f"{PLAYER_CARD_URL}{ittf_id}", headers=WTT_HEADERS, timeout=60
    )
    if response.status_code != 200:
        return {}

    payload = response.json()
    details_raw = payload.get("details")
    if not details_raw:
        return {}

    try:
        return json.loads(details_raw)
    except json.JSONDecodeError:
        return {}


def build_championships(card: dict[str, Any]) -> list[str]:
    titles: list[str] = []

    singles = card.get("singles_titles")
    doubles = card.get("doubles_titles")
    if singles:
        titles.append(f"Singles titles: {singles}")
    if doubles:
        titles.append(f"Doubles titles: {doubles}")

    stats_raw = card.get("stats")
    if stats_raw:
        try:
            stats = json.loads(stats_raw) if isinstance(stats_raw, str) else stats_raw
            career_titles = stats.get("career_titles") or stats.get("tournament_wins")
            if career_titles:
                titles.append(f"Career titles: {career_titles}")
        except json.JSONDecodeError:
            pass

    highlights_raw = card.get("highlights")
    if highlights_raw:
        try:
            highlights = (
                json.loads(highlights_raw)
                if isinstance(highlights_raw, str)
                else highlights_raw
            )
            for item in highlights:
                year = item.get("year")
                for key in ("singles", "doubles", "mixed"):
                    value = item.get(key)
                    if value:
                        titles.append(f"{year} {key}: {value}")
        except json.JSONDecodeError:
            pass

    if card.get("result") and card.get("event_name"):
        titles.append(f"{card['event_name']}: {card['result']}")

    return titles[:20]


def build_athlete_record(
    ranking_row: dict[str, Any],
    profile: dict[str, Any],
    card: dict[str, Any],
) -> dict[str, Any]:
    sub_event = ranking_row.get("SubEventCode", "")
    gender = GENDER_MAP.get(sub_event)
    if gender is None:
        raise ValueError(f"SubEventCode desconhecido: {sub_event}")

    photo = (
        profile.get("HeadshotR")
        or profile.get("HeadShot")
        or profile.get("HeadshotL")
    )

    hand = profile.get("Handedness") or card.get("Hand")
    age = parse_int(profile.get("Age") or ranking_row.get("Age"))
    height = parse_float(card.get("Height") or profile.get("Height"))

    return {
        "name": ranking_row.get("PlayerName") or profile.get("PlayerName"),
        "gender": gender,
        "ranking": parse_int(ranking_row.get("CurrentRank") or ranking_row.get("RankingPosition")),
        "age": age,
        "height": height,
        "hand": hand,
        "championships_won": build_championships(card),
        "photo_url": normalize_photo_url(photo),
        "updated_at": datetime.now(timezone.utc).isoformat(),
    }


def collect_gender_rankings(
    all_rankings: list[dict[str, Any]], sub_event_code: str, limit: int = 100
) -> list[dict[str, Any]]:
    filtered = [
        row
        for row in all_rankings
        if row.get("SubEventCode") == sub_event_code
    ]
    filtered.sort(key=lambda row: parse_int(row.get("CurrentRank")) or 9999)
    return filtered[:limit]


def scrape_top100() -> list[dict[str, Any]]:
    print("Buscando rankings SEN Singles na WTT...")
    all_rankings = fetch_rankings()
    targets = [
        ("MS", "masculino"),
        ("WS", "feminino"),
    ]

    athletes: list[dict[str, Any]] = []
    for sub_event, label in targets:
        rows = collect_gender_rankings(all_rankings, sub_event)
        print(f"  Top {len(rows)} {label}")

        for index, row in enumerate(rows, start=1):
            ittf_id = str(row.get("IttfId", "")).strip()
            name = row.get("PlayerName", "Desconhecido")
            print(f"    [{index}/{len(rows)}] {name}")

            profile: dict[str, Any] = {}
            card: dict[str, Any] = {}
            if ittf_id:
                try:
                    profile = fetch_player_profile(ittf_id)
                except requests.RequestException as exc:
                    print(f"      Aviso: perfil indisponível ({exc})")
                try:
                    card = fetch_player_card(ittf_id)
                except requests.RequestException as exc:
                    print(f"      Aviso: ficha indisponível ({exc})")
                time.sleep(0.15)

            athletes.append(build_athlete_record(row, profile, card))

    return athletes


def upsert_athletes(client: Client, athletes: list[dict[str, Any]]) -> None:
    if not athletes:
        print("Nenhum atleta coletado.")
        return

    print(f"Enviando {len(athletes)} atletas para o Supabase...")
    client.table("athletes").upsert(
        athletes,
        on_conflict="name,gender",
    ).execute()
    print("Upsert concluído.")


def get_client():
    url, key = load_config()
    client = create_client(url, key)
    client.auth.sign_in_with_password(
        {"email": APP_EMAIL, "password": APP_PASSWORD}
    )
    return client


def main() -> None:
    client = get_client()

    athletes = scrape_top100()
    upsert_athletes(client, athletes)

    male_count = sum(1 for athlete in athletes if athlete["gender"] == "male")
    female_count = sum(1 for athlete in athletes if athlete["gender"] == "female")
    print(f"Resumo: {male_count} masculino, {female_count} feminino.")


if __name__ == "__main__":
    main()
