"""Enriquecimento de títulos WTT + Wikipedia para atletas."""

from __future__ import annotations

import json
import re
from typing import Any

import requests

WIKI_HEADERS = {"User-Agent": "TM-Val/1.0 (tm-val-app; contact@colegioequacao.com)"}

MEDAL_PT = {"Gold": "Ouro", "Silver": "Prata", "Bronze": "Bronze"}
RESULT_PT = {
    "Gold": "Campeão",
    "Silver": "2° lugar",
    "Bronze": "3° lugar",
}

_YEAR_IN_TEXT = re.compile(r"\b(19|20)\d{2}\b")
_WIKI_LINK = re.compile(r"\[\[([^|\]]+\|)?([^\]]+)\]\]")
_WIKI_EXT_LINK = re.compile(r"\[https?://[^\]|]+(?:\|([^\]]+))?\]")
_WIKI_TEMPLATE = re.compile(r"\{\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\}", re.DOTALL)
_WIKI_REF = re.compile(r"<ref[^>]*>.*?</ref>", re.DOTALL | re.IGNORECASE)
_RAW_URL = re.compile(r"https?://\S+")
_WIKI_BOLD = re.compile(r"'{2,5}([^']+)'{2,5}")
_JUNK_TEXT = re.compile(
    r"On his birthday|access-date|website=|Cite web|cite web|archive\.org|"
    r"alternate link|dummyplayer|Headshot",
    re.I,
)

IMPORTANT_COMP = re.compile(
    r"olympic|olimp[ií]ada|world table tennis championship|world championship|"
    r"world team table tennis|table tennis world cup|campeonato mundial|mundial|"
    r"asian table tennis|asian cup|pan.?american",
    re.I,
)
WTT_EVENT = re.compile(
    r"\bwtt\b|grand smash|star contender|contender|cup finals|wtt finals|wtt champions",
    re.I,
)
NACIONAL_EVENT = re.compile(
    r"pan.?american|panameric|patc|south american|sul.?americ|"
    r"latin american|torneio nacional|campeonato brasileiro|nacional|americas cup",
    re.I,
)
PARTICIPATION_ONLY = re.compile(
    r"\b(group stage|round of \d+|^\d+(?:st|nd|rd|th) round|3rd round|quarterfinals?)\b",
    re.I,
)
TITLE_RESULT = re.compile(r"\b(champion|winner|campe[aã]o|vencedor|gold medal)\b", re.I)
RUNNER_UP = re.compile(r"\b(runner[- ]?up|silver medal)\b", re.I)
BRONZE_RESULT = re.compile(r"\b(bronze medal|bronze)\b", re.I)
SEMIFINAL = re.compile(r"\b(semi[- ]?finals?)\b", re.I)
QUARTERFINAL = re.compile(r"\b(quarter[- ]?finals?)\b", re.I)

GENERIC_CARD_MARKERS = ("Hina Hayata", "Sun Yingsha", "Lasko")

COMPETITION_ALIASES: list[tuple[re.Pattern[str], str]] = [
    (re.compile(r"pan.?american.*(?:championship|games)", re.I), "Pan-Americano"),
    (re.compile(r"world team table tennis", re.I), "Campeonato Mundial"),
    (re.compile(r"world table tennis championship", re.I), "Campeonato Mundial"),
    (re.compile(r"table tennis world cup|ittf world cup", re.I), "Copa do Mundo"),
    (re.compile(r"ittf mixed team world cup", re.I), "Copa do Mundo"),
    (re.compile(r"asian table tennis championship", re.I), "Campeonato Asiático"),
    (re.compile(r"ittf.?attu.?asian cup|asian cup", re.I), "Copa Asiática"),
    (re.compile(r"olympic|summer youth", re.I), "Olimpíadas"),
    (re.compile(r"pan american games", re.I), "Jogos Pan-Americanos"),
    (re.compile(r"americas cup", re.I), "Copa das Américas"),
]

MEDAL_LOCATION_EVENT: dict[tuple[str, str], str] = {
    ("2025", "China"): "WTT Grand Smash",
    ("2025", "United States"): "WTT Grand Smash",
    ("2026", "Singapore"): "WTT Grand Smash",
    ("2025", "Singapore"): "WTT Champions",
    ("2025", "Chongqing"): "WTT Champions",
    ("2025", "Macao"): "Copa do Mundo",
    ("2026", "Macao"): "Copa do Mundo",
    ("2025", "Yokohama"): "WTT Contender",
    ("2025", "Hong Kong"): "WTT",
    ("2026", "San Francisco"): "Copa das Américas",
    ("2025", "Doha"): "Campeonato Mundial",
    ("2026", "London"): "Campeonato Mundial",
    ("2025", "Rock Hill"): "Pan-Americano",
    ("2025", "Chengdu"): "Copa do Mundo",
    ("2025", "Bhubaneswar"): "Campeonato Asiático",
    ("2025", "Shenzhen"): "Copa Asiática",
    ("2026", "Haikou"): "Copa Asiática",
}

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
    "Rock Hill": "Rock Hill",
}


def _location_lookup_keys(location: str) -> list[str]:
    keys = [location]
    for source, target in LOCATION_PT.items():
        if location == target:
            keys.append(source)
        elif location == source:
            keys.append(target)
    return keys


def translate_highlight(text: str) -> str:
    text = text.replace("Champions", "\x00CHAMPIONS\x00")
    text = re.sub(r"\bChampion\b", "Campeão", text)
    text = text.replace("\x00CHAMPIONS\x00", "Champions")
    replacements = [
        ("World Table Tennis Championships", "Campeonato Mundial"),
        ("World Championships", "Campeonato Mundial"),
        ("World Team Table Tennis Championships", "Campeonato Mundial"),
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
        ("Men's singles", "Simples"),
        ("Women's singles", "Simples"),
        ("Men's doubles", "Duplas"),
        ("Women's doubles", "Duplas"),
        ("Men's team", "Equipe"),
        ("Women's team", "Equipe"),
        ("Singles", "Simples"),
        ("Doubles", "Duplas"),
        ("Team", "Equipe"),
        ("World Campeonato Mundial", "Campeonato Mundial"),
        ("World Championship", "Campeonato Mundial"),
        ("World Campeãoship", "Campeonato Mundial"),
        ("Winner", "Campeão"),
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


def _discipline_to_pt(value: str) -> str:
    lower = clean_wiki_text(value).lower()
    if "mixed doubles" in lower or lower == "mixed":
        return "Duplas mistas"
    if "mixed team" in lower:
        return "Equipe mista"
    if "doubles" in lower or "duplas" in lower:
        return "Duplas"
    if "team" in lower or "equipe" in lower:
        return "Equipe"
    if "singles" in lower or "simples" in lower:
        return "Simples"
    return translate_highlight(value) if value else "Simples"


def _extract_location(part1: str, part2: str, year: str | None) -> str:
    for part in (part1, part2):
        loc = clean_wiki_text(part)
        if not loc:
            continue
        if year:
            loc = re.sub(rf"^{re.escape(year)}\s*", "", loc).strip()
        loc = re.sub(r"^\d{4}\s*", "", loc).strip()
        lower = loc.lower()
        if lower in {"singles", "doubles", "mixed doubles", "team", "mixed team", "simples", "duplas", "equipe"}:
            continue
        if loc:
            return localize_place(loc)
    return "?"


def _resolve_competition_name(part1: str, part2: str, raw: str, year: str | None, location: str) -> str:
    combined = f"{part1} {part2} {raw}"
    for pattern, name in COMPETITION_ALIASES:
        if pattern.search(combined):
            return name

    if year and location != "?":
        for loc in _location_lookup_keys(location):
            mapped = MEDAL_LOCATION_EVENT.get((year, loc))
            if mapped:
                return mapped

    lower = combined.lower()
    if "grand smash" in lower or re.search(r"\bsmash\b", lower):
        return "WTT Grand Smash"
    if "star contender" in lower:
        return "WTT Star Contender"
    if "contender" in lower:
        return "WTT Contender"
    if "wtt champions" in lower:
        return "WTT Champions"
    if "cup finals" in lower or "wtt finals" in lower:
        return "WTT Finals"
    if WTT_EVENT.search(combined):
        return _format_wtt_event_name(part1 or part2)

    cleaned = translate_highlight(clean_wiki_text(part1 or part2))
    return cleaned or "Torneio"


def _format_medal_line(medal_place: str, params: list[str]) -> str | None:
    result_pt = RESULT_PT.get(medal_place.title())
    if not result_pt:
        return None

    part1 = clean_wiki_text(params[0]) if params else ""
    part2 = clean_wiki_text(params[1]) if len(params) > 1 else ""
    raw = " ".join(params)
    year = year_from_parts(part1, part2, raw) or "?"
    location = _extract_location(part1, part2, year)
    category = _discipline_to_pt(part2 or part1)
    comp_name = _resolve_competition_name(part1, part2, raw, year, location)

    if PARTICIPATION_ONLY.search(raw) and result_pt != "Campeão":
        return None
    if result_pt != "Campeão" and WTT_EVENT.search(comp_name) and medal_place.title() != "Gold":
        return None

    location_year = f"{location} {year}".strip()
    return f"{comp_name}: {result_pt} ({location_year} — {category})"


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
    if re.search(r"pan.?american.*championship", event, re.I):
        return "Pan-Americano"
    if re.search(r"table tennis world cup", event, re.I):
        return "Copa do Mundo"
    if re.search(r"world table tennis championship", event, re.I):
        return "Campeonato Mundial"
    if re.search(r"olympic", event, re.I):
        return "Olimpíadas"
    if re.search(r"pan american games", event, re.I):
        return "Jogos Pan-Americanos"
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


def _infer_bullet_category(event: str, detail: str) -> str | None:
    lower = detail.lower()
    if "mixed" in lower or "mista" in lower:
        return "Duplas mistas"
    if "doubles" in lower or "duplas" in lower:
        return "Duplas"
    event_lower = event.lower()
    if "mixed doubles" in event_lower:
        return "Duplas mistas"
    if "singles" in event_lower or "simples" in event_lower:
        return "Simples"
    return None


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
    year = year_from_parts(detail) or "?"
    remainder = detail.replace(year, "", 1).strip() if year != "?" else detail
    if year != "?" and (not remainder or remainder == year):
        if re.search(r"pan-americano|campeonato mundial|copa do mundo", event_name, re.I):
            return None
        line = f"{event_name}: {result_pt} ({year})"
        return translate_highlight(line)
    location = remainder or detail or year
    category = _infer_bullet_category(event, detail)
    if category:
        line = f"{event_name}: {result_pt} ({location} {year} — {category})"
    else:
        line = f"{event_name}: {result_pt} ({location} {year})"
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
    body = _WIKI_REF.sub("", body)
    body = clean_wiki_text(body)
    if not body or _RAW_URL.search(body) or _JUNK_TEXT.search(body):
        return []

    if ":" not in body:
        return []

    event, rest = body.split(":", 1)
    event = event.strip()
    rest = rest.strip()
    if not event or not rest or not _is_relevant_wiki_event(event):
        return []

    paren_match = re.search(r"\(([^)]+)\)", rest)
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


def _parse_wiki_prose_titles(wikitext: str) -> list[str]:
    plain = clean_wiki_text(_WIKI_REF.sub("", wikitext))
    titles: list[str] = []

    if re.search(
        r"WTT Contender in Buenos Aires.*mixed doubles.*(?:Bruna Takahashi|Takahashi)",
        plain,
        re.I | re.S,
    ):
        titles.append("WTT Contender: Campeão (Buenos Aires 2025 — Duplas mistas)")

    if re.search(
        r"Pan American Table Tennis Championships champion.*mixed doubles.*(?:Bruna Takahashi|Takahashi)",
        plain,
        re.I | re.S,
    ):
        titles.append("Pan-Americano: Campeão (Rock Hill 2025 — Duplas mistas)")

    return titles


def _is_generic_card_highlight(value: str) -> bool:
    return any(marker in value for marker in GENERIC_CARD_MARKERS)


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
            formatted = _format_medal_line(medal_place, params)
            if formatted:
                titles.append(formatted)

        for line in wikitext.split("\n"):
            titles.extend(_parse_wiki_bullet_line(line))

        titles.extend(_parse_wiki_prose_titles(wikitext))

    except requests.RequestException:
        pass

    return titles


def _is_junk_title(text: str) -> bool:
    if not text:
        return True
    if _RAW_URL.search(text) or "{{" in text or "[http" in text.lower():
        return True
    if _JUNK_TEXT.search(text):
        return True
    if text.startswith("Último resultado:"):
        return True
    if re.match(r"^\d{4}\s+(Ouro|Prata|Bronze)\s+—", text):
        return True
    if text.startswith("WTT Star Contender: Campeão") and "(" not in text:
        return True
    return False


def _normalize_identity_event(event: str) -> str:
    lower = event.lower()
    if "campeonato mundial" in lower or "world table tennis" in lower:
        return "campeonato mundial"
    if "pan-americano" in lower or "pan american" in lower:
        return "pan-americano"
    if "copa do mundo" in lower or "world cup" in lower:
        return "copa do mundo"
    if "wtt grand smash" in lower or "grand smash" in lower:
        return "wtt grand smash"
    if "wtt star contender" in lower:
        return "wtt star contender"
    if "wtt contender" in lower:
        return "wtt contender"
    if "wtt champions" in lower:
        return "wtt champions"
    return lower


def _title_identity(title: str) -> tuple[str, str, str, str]:
    year = year_from_parts(title) or ""
    lower = title.lower()
    category = ""
    if "duplas mistas" in lower or "— mista" in lower:
        category = "mista"
    elif "duplas" in lower:
        category = "duplas"
    elif "equipe" in lower:
        category = "equipe"
    elif "simples" in lower:
        category = "simples"
    else:
        category = "simples"

    raw_event = title.split(":", 1)[0].strip() if ":" in title else title
    event = _normalize_identity_event(raw_event)
    location = ""
    paren = re.search(r"\(([^)]+)\)", title)
    if paren:
        inner = paren.group(1).lower()
        location = re.sub(r"\b(19|20)\d{2}\b", "", inner).split("—")[0].strip()
        location = re.sub(r"\s+", " ", location).strip(" ,")
    return (event, year, location, category)


def _title_priority(title: str) -> int:
    lower = title.lower()
    if "campeão" in lower or "campeã" in lower:
        return 4
    if "2° lugar" in lower or "prata" in lower:
        return 3
    if "3° lugar" in lower or "bronze" in lower:
        return 2
    if "4° lugar" in lower or "5-8" in lower:
        return 1
    return 0


def merge_titles(*sources: list[str]) -> list[str]:
    best: dict[tuple[str, str, str, str], tuple[int, str]] = {}
    order: list[tuple[str, str, str, str]] = []

    for source in sources:
        for raw in source:
            text = translate_highlight(clean_wiki_text(raw.strip()))
            if _is_junk_title(text):
                continue
            if _is_generic_card_highlight(text):
                continue

            key = _title_identity(text)
            priority = _title_priority(text)
            if key not in best:
                order.append(key)
                best[key] = (priority, text)
            elif priority > best[key][0]:
                best[key] = (priority, text)

    seen_text: set[str] = set()
    merged: list[str] = []
    for key in order:
        text = best[key][1]
        if text in seen_text:
            continue
        seen_text.add(text)
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
