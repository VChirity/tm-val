"""Enriquecimento de títulos WTT + Wikipedia para atletas."""

from __future__ import annotations

import json
import re
from typing import Any

import requests

WIKI_HEADERS = {"User-Agent": "TM-Val/1.0 (tm-val-app; contact@colegioequacao.com)"}

MEDAL_PT = {"Gold": "Ouro", "Silver": "Prata", "Bronze": "Bronze"}

_YEAR_IN_TEXT = re.compile(r"\b(19|20)\d{2}\b")
_WIKI_LINK = re.compile(r"\[\[([^|\]]+\|)?([^\]]+)\]\]")


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
        "Team": "Equipe",
        "Singles": "Simples",
        "Doubles": "Duplas",
        "Mixed doubles": "Duplas mistas",
        "Mixed team": "Equipe mista",
    }
    for source, target in replacements.items():
        text = text.replace(source, target)
    return text


def clean_wiki_text(value: str) -> str:
    text = _WIKI_LINK.sub(r"\2", value)
    text = re.sub(r"<[^>]+>", "", text)
    text = text.replace("{{CHN}}", "China")
    text = text.replace("{{chn}}", "China")
    return re.sub(r"\s+", " ", text).strip()


def year_from_parts(*parts: str) -> str | None:
    for part in parts:
        if not part:
            continue
        match = _YEAR_IN_TEXT.search(part)
        if match:
            return match.group(0)
    return None


def _split_tournament_list(value: str) -> list[str]:
    parts = re.split(r",\s*|\t|\n", value)
    return [p.strip() for p in parts if p.strip()]


def _split_wiki_params(text: str) -> list[str]:
    """Divide parâmetros de template por |, ignorando pipes dentro de [[links]]."""
    parts: list[str] = []
    current: list[str] = []
    link_depth = 0
    for ch in text:
        if ch == "[":
            link_depth += 1
        elif ch == "]":
            link_depth = max(0, link_depth - 1)
        elif ch == "|" and link_depth == 0:
            parts.append("".join(current))
            current = []
            continue
        current.append(ch)
    parts.append("".join(current))
    return parts


def _extract_medal_templates(wikitext: str) -> list[tuple[str, list[str]]]:
    """Extrai {{MedalGold|...}}, {{MedalSilver|...}} etc. com pipes aninhados."""
    results: list[tuple[str, list[str]]] = []
    opener = re.compile(r"\{\{(Medal(?:Gold|Silver|Bronze))\|", re.I)
    for match in opener.finditer(wikitext):
        depth = 2
        i = match.end()
        content: list[str] = []
        while i < len(wikitext):
            if wikitext.startswith("{{", i):
                depth += 2
                content.append("{{")
                i += 2
                continue
            if wikitext.startswith("}}", i):
                depth -= 2
                if depth == 0:
                    break
                content.append("}}")
                i += 2
                continue
            content.append(wikitext[i])
            i += 1

        medal_type = match.group(1)
        place = medal_type.replace("Medal", "", 1)
        params = _split_wiki_params("".join(content))
        results.append((place, params))
    return results


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


def _wiki_page_title(player_name: str) -> str | None:
    search = requests.get(
        "https://en.wikipedia.org/w/api.php",
        headers=WIKI_HEADERS,
        params={
            "action": "query",
            "list": "search",
            "srsearch": f"{player_name} table tennis",
            "srlimit": 5,
            "format": "json",
        },
        timeout=15,
    )
    search.raise_for_status()
    hits = search.json().get("query", {}).get("search", [])
    if not hits:
        return None

    family = player_name.split()[-1].lower() if player_name.split() else ""
    for hit in hits:
        title = hit.get("title", "")
        if family and family in title.lower():
            return title
    return hits[0]["title"]


def titles_from_wikipedia(player_name: str) -> list[str]:
    titles: list[str] = []
    try:
        page = _wiki_page_title(player_name)
        if not page:
            return titles

        parse_resp = requests.get(
            "https://en.wikipedia.org/w/api.php",
            headers=WIKI_HEADERS,
            params={
                "action": "parse",
                "page": page,
                "prop": "wikitext",
                "format": "json",
            },
            timeout=20,
        )
        parse_resp.raise_for_status()
        wikitext = parse_resp.json()["parse"]["wikitext"]["*"]

        for medal_place, params in _extract_medal_templates(wikitext):
            place = MEDAL_PT.get(medal_place.title(), medal_place)
            raw_combined = " ".join(params)
            part1 = clean_wiki_text(params[0]) if params else ""
            part2 = clean_wiki_text(params[1]) if len(params) > 1 else ""
            year = year_from_parts(part1, part2, raw_combined) or "?"

            if re.search(r"olympic|jogos ol|summer youth", raw_combined, re.I):
                event = part2 or part1
                comp = "Olimpíadas"
            elif part2:
                event = part2
                comp = part1
            else:
                event = ""
                comp = part1

            line = f"{year} {place} — {translate_highlight(comp)}"
            if event:
                line += f" ({translate_highlight(event)})"
            titles.append(line)

        for line in wikitext.split("\n"):
            stripped = line.strip()
            if not stripped.startswith("*"):
                continue
            if not re.search(
                r"WTT|World Championship|Olympic|Grand Smash|Singapore Smash|"
                r"Contender|Cup Finals|Asian Championship|World Cup|Olimp",
                stripped,
                re.I,
            ):
                continue
            clean = clean_wiki_text(stripped.lstrip("* ").strip())
            if _YEAR_IN_TEXT.search(clean):
                titles.append(translate_highlight(clean))

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


def sort_titles_by_year(titles: list[str]) -> list[str]:
    def sort_key(title: str) -> tuple[int, str]:
        year = year_from_parts(title) or "0000"
        return (int(year) if year.isdigit() else 0, title)

    summary = [t for t in titles if "Títulos em" in t or "Títulos na carreira" in t]
    rest = [t for t in titles if t not in summary]
    rest.sort(key=sort_key, reverse=True)
    return summary + rest


def build_championships(card: dict[str, Any], player_name: str) -> list[str]:
    card_titles = titles_from_player_card(card)
    wiki_titles = titles_from_wikipedia(player_name)
    return sort_titles_by_year(merge_titles(card_titles, wiki_titles))
