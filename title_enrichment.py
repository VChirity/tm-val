"""Enriquecimento de títulos WTT + Wikipedia para atletas."""

from __future__ import annotations

import json
import re
from typing import Any

import requests

WIKI_HEADERS = {"User-Agent": "TM-Val/1.0 (tm-val-app; contact@colegioequacao.com)"}

MEDAL_PT = {"Gold": "Ouro", "Silver": "Prata", "Bronze": "Bronze"}


def translate_highlight(text: str) -> str:
    replacements = {
        "Singles titles:": "Títulos em simples:",
        "Doubles titles:": "Títulos em duplas:",
        "Career titles:": "Títulos na carreira:",
        " singles:": " simples:",
        " doubles:": " duplas:",
        " mixed:": " mista:",
        "Winner": "Campeão",
        "Champion": "Campeão",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return text


def _split_tournament_list(value: str) -> list[str]:
    parts = re.split(r",\s*|\t|\n", value)
    return [p.strip() for p in parts if p.strip()]


def titles_from_player_card(card: dict[str, Any]) -> list[str]:
    titles: list[str] = []

    singles = card.get("singles_titles")
    doubles = card.get("doubles_titles")
    if singles:
        titles.append(translate_highlight(f"Singles titles: {singles}"))
    if doubles:
        titles.append(translate_highlight(f"Doubles titles: {doubles}"))

    stats_raw = card.get("stats")
    if stats_raw:
        try:
            stats = json.loads(stats_raw) if isinstance(stats_raw, str) else stats_raw
            career_titles = stats.get("career_titles") or stats.get("tournament_wins")
            if career_titles:
                titles.append(translate_highlight(f"Career titles: {career_titles}"))
        except (json.JSONDecodeError, TypeError):
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
                    if not value:
                        continue
                    for tournament in _split_tournament_list(str(value)):
                        titles.append(
                            translate_highlight(f"{year} {key}: {tournament}")
                        )
        except (json.JSONDecodeError, TypeError):
            pass

    if card.get("result") and card.get("event_name"):
        titles.append(f"{card['event_name']}: {card['result']}")

    if card.get("last_result"):
        titles.append(f"Último resultado: {card['last_result']}")

    return titles


def titles_from_wikipedia(player_name: str) -> list[str]:
    titles: list[str] = []
    try:
        search = requests.get(
            "https://en.wikipedia.org/w/api.php",
            headers=WIKI_HEADERS,
            params={
                "action": "query",
                "list": "search",
                "srsearch": f"{player_name} table tennis",
                "srlimit": 3,
                "format": "json",
            },
            timeout=12,
        )
        search.raise_for_status()
        hits = search.json().get("query", {}).get("search", [])
        if not hits:
            return titles

        page = hits[0]["title"]
        parse_resp = requests.get(
            "https://en.wikipedia.org/w/api.php",
            headers=WIKI_HEADERS,
            params={
                "action": "parse",
                "page": page,
                "prop": "wikitext",
                "format": "json",
            },
            timeout=12,
        )
        parse_resp.raise_for_status()
        wikitext = parse_resp.json()["parse"]["wikitext"]["*"]

        for block in re.findall(r"\{\{Med(?:al|alCompetition)[^}]*\}\}", wikitext, re.S):
            year_m = re.search(r"year\s*=\s*([^|\n}]+)", block, re.I)
            comp_m = re.search(r"competition\s*=\s*([^|\n}]+)", block, re.I)
            event_m = re.search(r"event\s*=\s*([^|\n}]+)", block, re.I)
            place_m = re.search(r"\b(Gold|Silver|Bronze)\b", block, re.I)
            if not (comp_m and place_m):
                continue
            year = year_m.group(1).strip() if year_m else "?"
            comp = comp_m.group(1).strip()
            place = MEDAL_PT.get(place_m.group(1), place_m.group(1))
            event = event_m.group(1).strip() if event_m else ""
            line = f"{year} {place} — {comp}"
            if event:
                line += f" ({event})"
            titles.append(line)

        for line in wikitext.split("\n"):
            stripped = line.strip()
            if not stripped.startswith("*"):
                continue
            if not re.search(
                r"WTT|World Championship|Olympic|Grand Smash|Singapore Smash|"
                r"Contender|Cup Finals|Asian Championship|World Cup",
                stripped,
                re.I,
            ):
                continue
            clean = re.sub(r"\[\[([^|\]]+\|)?([^\]]+)\]\]", r"\2", stripped)
            clean = re.sub(r"<[^>]+>", "", clean).strip("* ").strip()
            year_m = re.match(r"(\d{4})\s*[—–-]?\s*", clean)
            if year_m:
                titles.append(clean)
            elif re.search(r"\b(19|20)\d{2}\b", clean):
                titles.append(clean)

    except requests.RequestException:
        pass

    return titles


def merge_titles(*sources: list[str]) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for source in sources:
        for raw in source:
            text = translate_highlight(raw.strip())
            if not text or text in seen:
                continue
            seen.add(text)
            merged.append(text)
    return merged


def build_championships(card: dict[str, Any], player_name: str) -> list[str]:
    card_titles = titles_from_player_card(card)
    wiki_titles = titles_from_wikipedia(player_name)
    return merge_titles(card_titles, wiki_titles)
