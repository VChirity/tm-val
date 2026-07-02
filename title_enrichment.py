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
_WIKI_EXT_LINK = re.compile(r"\[https?://[^\]|]+(?:\|([^\]]+))?\]")
_WIKI_TEMPLATE = re.compile(r"\{\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\}", re.DOTALL)
_WIKI_REF = re.compile(r"<ref[^>]*>.*?</ref>", re.DOTALL | re.IGNORECASE)
_RAW_URL = re.compile(r"https?://\S+")
_WIKI_BOLD = re.compile(r"'{2,5}([^']+)'{2,5}")

IMPORTANT_COMP = re.compile(
    r"olympic|olimp[ií]ada|world table tennis championship|world championship|"
    r"table tennis world cup|campeonato mundial|mundial",
    re.I,
)
WTT_EVENT = re.compile(
    r"\bwtt\b|grand smash|star contender|contender|cup finals|wtt finals|wtt champions",
    re.I,
)
NACIONAL_EVENT = re.compile(
    r"pan.?american|panameric|patc|south american|sul.?americ|"
    r"latin american|torneio nacional|campeonato brasileiro|nacional",
    re.I,
)
PARTICIPATION_ONLY = re.compile(
    r"\b(group stage|round of \d+|^\d+(?:st|nd|rd|th) round|3rd round)\b",
    re.I,
)
TITLE_RESULT = re.compile(r"\b(champion|winner|campe[aã]o|vencedor|gold medal)\b", re.I)
RUNNER_UP = re.compile(r"\b(runner[- ]?up|silver medal)\b", re.I)
BRONZE_RESULT = re.compile(r"\b(bronze medal|bronze)\b", re.I)
SEMIFINAL = re.compile(r"\b(semi[- ]?finals?)\b", re.I)
QUARTERFINAL = re.compile(r"\b(quarter[- ]?finals?)\b", re.I)

LOCATION_PT = {
    "Singapore": "Singapura",
    "Macau": "Macau",
    "Macao": "Macau",
    "Hong Kong": "Hong Kong",
    "United States": "Estados Unidos",
    "China": "China",
    "Doha": "Doha",
    "Buenos Aires": "Buenos Aires",
    "Foz do Iguaçu": "Foz do Iguaçu",
}


def translate_highlight(text: str) -> str:
    replacements = [
        ("World Table Tennis Championships", "Campeonato Mundial"),
        ("World Championships", "Campeonato Mundial"),
        ("Table Tennis World Cup", "Copa do Mundo"),
        ("Pan American Table Tennis Championships", "Pan-Americano"),
        ("Pan American Games", "Jogos Pan-Americanos"),
        ("Olympic Games", "Olimpíadas"),
        ("Singles titles:", "Títulos em simples:"),
        ("Doubles titles:", "Títulos em duplas:"),
        ("Career titles:", "Títulos na carreira:"),
        (" singles:", " simples:"),
        (" doubles:", " duplas:"),
        (" mixed:", " mista:"),
        ("Mixed doubles", "Duplas mistas"),
        ("Mixed team", "Equipe mista"),
        ("Singles", "Simples"),
        ("Doubles", "Duplas"),
        ("Team", "Equipe"),
        ("World Campeonato Mundial", "Campeonato Mundial"),
        ("World Championship", "Campeonato Mundial"),
        ("Winner", "Campeão"),
        ("Champion", "Campeão"),
        ("Gold", "Ouro"),
        ("Silver", "Prata"),
        ("Bronze", "Bronze"),
    ]
    for source, target in replacements:
        text = text.replace(source, target)
    return text


def clean_wiki_text(value: str) -> str:
    text = value
    text = _WIKI_REF.sub("", text)
    text = _WIKI_TEMPLATE.sub("", text)
    text = _WIKI_LINK.sub(r"\2", text)
    text = _WIKI_EXT_LINK.sub(lambda m: (m.group(1) or "").strip(), text)
    text = _WIKI_BOLD.sub(r"\1", text)
    text = re.sub(r"<[^>]+>", "", text)
    text = _RAW_URL.sub("", text)
    text = text.replace("{{CHN}}", "China")
    text = text.replace("{{chn}}", "China")
    text = re.sub(r"\(\s*archived[^)]*\)", "", text, flags=re.I)
    text = re.sub(r"\(\s*alternate link[^)]*\)", "", text, flags=re.I)
    text = text.replace("]", "").replace("[", "")
    text = re.sub(r"\s+", " ", text).strip(" .,;")
    return text


def localize_place(text: str) -> str:
    out = text
    for source, target in LOCATION_PT.items():
        out = re.sub(rf"\b{re.escape(source)}\b", target, out)
    return out


def year_from_parts(*parts: str) -> str | None:
    for part in parts:
        if not part:
            continue
        match = _YEAR_IN_TEXT.search(part)
        if match:
            return match.group(0)
    return None


def title_category(title: str) -> str:
    lower = title.lower()
    if WTT_EVENT.search(lower):
        return "wtt"
    if NACIONAL_EVENT.search(lower) or re.search(
        r"\b(lima|santiago|havana|guaynabo|asunción|cartagena|san juan|"
        r"toronto|santo domingo|rock hill|san salvador)\b",
        lower,
    ):
        return "nacional"
    return "outros"


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


def _format_wtt_event_name(event: str) -> str:
    event = clean_wiki_text(event)
    event = translate_highlight(event)
    lower = event.lower()
    if "grand smash" in lower:
        return "WTT Grand Smash"
    if "star contender" in lower:
        return "WTT Star Contender"
    if "contender" in lower:
        return "WTT Contender"
    if "cup finals" in lower or "wtt finals" in lower:
        return "WTT Finals"
    if "wtt champions" in lower or re.search(r"\bwtt\b.*\bchampions\b", lower):
        return "WTT Champions"
    if "world cup" in lower and "table tennis" in lower:
        return "Copa do Mundo"
    if lower.startswith("wtt "):
        return event
    if WTT_EVENT.search(event):
        return f"WTT {event}" if not event.upper().startswith("WTT") else event
    return event


def _normalize_event_name(event: str) -> str:
    event = clean_wiki_text(event)
    event = translate_highlight(event)
    if WTT_EVENT.search(event):
        return _format_wtt_event_name(event)
    return event


def _expand_parenthetical_entries(details: str) -> list[str]:
    details = localize_place(clean_wiki_text(details))
    entries: list[str] = []
    for chunk in _split_tournament_list(details):
        chunk = chunk.strip()
        if not chunk:
            continue
        year = year_from_parts(chunk)
        if year and chunk.isdigit():
            entries.append(year)
            continue
        entries.append(chunk)
    return entries


def _result_to_pt(result: str, event: str) -> str | None:
    result = clean_wiki_text(result)
    if not result or PARTICIPATION_ONLY.search(result):
        return None

    important = bool(IMPORTANT_COMP.search(event))
    wtt = bool(WTT_EVENT.search(event))

    if TITLE_RESULT.search(result):
        return "Campeão"
    if RUNNER_UP.search(result):
        return "2° lugar" if important and not wtt else None
    if BRONZE_RESULT.search(result):
        return "3° lugar" if important and not wtt else None
    if SEMIFINAL.search(result):
        return "4° lugar" if important else None
    if QUARTERFINAL.search(result):
        return "5-8° lugar" if important else None
    return None


def _format_bullet_title(event: str, result_pt: str, detail: str) -> str | None:
    event_name = _normalize_event_name(event)
    detail = localize_place(clean_wiki_text(detail))
    year = year_from_parts(detail)
    remainder = detail.replace(year, "", 1).strip() if year else detail
    if year and not remainder:
        location = year
    else:
        location = detail or year or "?"
    line = f"{event_name}: {result_pt} ({location})"
    return translate_highlight(line)


def _is_relevant_wiki_event(event: str) -> bool:
    event = clean_wiki_text(event)
    return bool(
        WTT_EVENT.search(event)
        or IMPORTANT_COMP.search(event)
        or NACIONAL_EVENT.search(event)
        or re.search(
            r"pan.?american|world cup|grand smash|smash|contender|olympic|mundial",
            event,
            re.I,
        )
    )


def _parse_wiki_bullet_line(line: str) -> list[str]:
    stripped = line.strip()
    if not stripped.startswith("*"):
        return []
    if stripped.startswith("* {") or stripped.startswith("* {{") or stripped.startswith("* ["):
        return []

    body = stripped.lstrip("* ").strip()
    body = clean_wiki_text(body)
    if not body or _RAW_URL.search(body):
        return []

    if ":" not in body:
        return []

    event, rest = body.split(":", 1)
    event = event.strip()
    rest = rest.strip()
    if not event or not rest or not _is_relevant_wiki_event(event):
        return []

    paren_match = re.search(r"\(([^)]+)\)\.?$", rest)
    if not paren_match:
        return []

    details_raw = paren_match.group(1)
    result_raw = rest[: paren_match.start()].strip(" .")
    result_pt = _result_to_pt(result_raw, event)
    if not result_pt:
        return []

    titles: list[str] = []
    for detail in _expand_parenthetical_entries(details_raw):
        formatted = _format_bullet_title(event, result_pt, detail)
        if formatted:
            titles.append(formatted)
    return titles


def _format_card_highlight(year: str, key: str, tournament: str) -> str:
    tournament = translate_highlight(clean_wiki_text(tournament))
    key_pt = {"singles": "simples", "doubles": "duplas", "mixed": "mista"}.get(
        key, key
    )
    if WTT_EVENT.search(tournament) or re.search(
        r"\b(smash|contender|cup finals)\b", tournament, re.I
    ):
        if not tournament.upper().startswith("WTT"):
            tournament = f"WTT {tournament}"
    return f"{year} {key_pt}: {tournament}"


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
                        titles.append(_format_card_highlight(str(year), key, tournament))
        except (json.JSONDecodeError, TypeError):
            pass

    if card.get("result") and card.get("event_name"):
        event = translate_highlight(clean_wiki_text(str(card["event_name"])))
        result = translate_highlight(clean_wiki_text(str(card["result"])))
        if TITLE_RESULT.search(result):
            titles.append(f"{_format_wtt_event_name(event)}: {result_pt_or(result)}")

    if card.get("last_result"):
        titles.append(f"Último resultado: {clean_wiki_text(str(card['last_result']))}")

    return titles


def result_pt_or(result: str) -> str:
    mapped = _result_to_pt(result, "")
    return mapped or translate_highlight(result)


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

            comp = translate_highlight(comp)
            event = translate_highlight(event)
            line = f"{year} {place} — {comp}"
            if event:
                line += f" ({event})"
            titles.append(line)

        for line in wikitext.split("\n"):
            titles.extend(_parse_wiki_bullet_line(line))

    except requests.RequestException:
        pass

    return titles


def merge_titles(*sources: list[str]) -> list[str]:
    seen: set[str] = set()
    merged: list[str] = []
    for source in sources:
        for raw in source:
            text = translate_highlight(clean_wiki_text(raw.strip()))
            if not text or text in seen:
                continue
            if _RAW_URL.search(text) or "{{" in text or "[http" in text.lower():
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
