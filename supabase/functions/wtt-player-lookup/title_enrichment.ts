const WIKI_HEADERS = { "User-Agent": "TM-Val/1.0 (tm-val-app)" };

const MEDAL_PT: Record<string, string> = {
  Gold: "Ouro",
  Silver: "Prata",
  Bronze: "Bronze",
};

const RESULT_PT: Record<string, string> = {
  Gold: "Campeão",
  Silver: "2° lugar",
  Bronze: "3° lugar",
};

const YEAR_IN_TEXT = /\b(19|20)\d{2}\b/;
const WIKI_LINK = /\[\[([^|\]]+\|)?([^\]]+)\]\]/g;
const WIKI_EXT_LINK = /\[https?:\/\/[^\]|]+(?:\|([^\]]+))?\]/g;
const WIKI_TEMPLATE = /\{\{[^{}]*(?:\{[^{}]*\}[^{}]*)*\}\}/gs;
const WIKI_REF = /<ref[^>]*>.*?<\/ref>/gis;
const RAW_URL = /https?:\/\/\S+/;
const WIKI_BOLD = /'{2,5}([^']+)'{2,5}/g;
const JUNK_TEXT =
  /On his birthday|access-date|website=|Cite web|cite web|archive\.org|alternate link|dummyplayer|Headshot/i;

const IMPORTANT_COMP =
  /olympic|olimp[ií]ada|world table tennis championship|world championship|world team table tennis|table tennis world cup|campeonato mundial|mundial|asian table tennis|asian cup|pan.?american/i;
const WTT_EVENT =
  /\bwtt\b|grand smash|star contender|contender|cup finals|wtt finals|wtt champions/i;
const NACIONAL_EVENT =
  /pan.?american|panameric|patc|south american|sul.?americ|latin american|torneio nacional|campeonato brasileiro|nacional|americas cup/i;
const PARTICIPATION_ONLY =
  /\b(group stage|round of \d+|^\d+(?:st|nd|rd|th) round|3rd round|quarterfinals?)\b/i;
const TITLE_RESULT =
  /\b(champion|winner|campe[aã]o|vencedor|gold medal)\b/i;
const RUNNER_UP = /\b(runner[- ]?up|silver medal)\b/i;
const BRONZE_RESULT = /\b(bronze medal|bronze)\b/i;
const SEMIFINAL = /\b(semi[- ]?finals?)\b/i;
const QUARTERFINAL = /\b(quarter[- ]?finals?)\b/i;

const GENERIC_CARD_MARKERS = ["Hina Hayata", "Sun Yingsha", "Lasko"];

const COMPETITION_ALIASES: Array<[RegExp, string]> = [
  [/pan.?american.*(?:championship|games)/i, "Pan-Americano"],
  [/world team table tennis/i, "Campeonato Mundial"],
  [/world table tennis championship/i, "Campeonato Mundial"],
  [/table tennis world cup|ittf world cup/i, "Copa do Mundo"],
  [/ittf mixed team world cup/i, "Copa do Mundo"],
  [/asian table tennis championship/i, "Campeonato Asiático"],
  [/ittf.?attu.?asian cup|asian cup/i, "Copa Asiática"],
  [/olympic|summer youth/i, "Olimpíadas"],
  [/pan american games/i, "Jogos Pan-Americanos"],
  [/americas cup/i, "Copa das Américas"],
];

const MEDAL_LOCATION_EVENT: Record<string, string> = {
  "2025|China": "WTT Grand Smash",
  "2025|United States": "WTT Grand Smash",
  "2026|Singapore": "WTT Grand Smash",
  "2025|Singapore": "WTT Grand Smash",
  "2024|Singapore": "WTT Grand Smash",
  "2023|Singapore": "WTT Grand Smash",
  "2022|Singapore": "WTT Grand Smash",
  "2025|Chongqing": "WTT Champions",
  "2025|Macao": "WTT Champions",
  "2024|Macao": "WTT Champions",
  "2023|Macao": "WTT Champions",
  "2022|Macao": "WTT Champions",
  "2026|Macao": "Copa do Mundo",
  "2025|Yokohama": "WTT Contender",
  "2025|Hong Kong": "WTT Finals",
  "2025|Malmö": "WTT Grand Smash",
  "2025|Malmo": "WTT Grand Smash",
  "2025|Montpellier": "WTT Champions",
  "2026|San Francisco": "Copa das Américas",
  "2025|Doha": "Campeonato Mundial",
  "2026|London": "Campeonato Mundial",
  "2025|Rock Hill": "Pan-Americano",
  "2025|Chengdu": "Copa do Mundo",
  "2025|Bhubaneswar": "Campeonato Asiático",
  "2025|Shenzhen": "Copa Asiática",
  "2026|Haikou": "Copa Asiática",
};

const WTT_FINALS_DEFAULT_LOCATION: Record<string, string> = {
  "2021": "Singapura",
  "2022": "Xinxiang",
  "2023": "Doha",
  "2024": "Fukuoka",
  "2025": "Hong Kong",
};

const PRESTIGIOUS_WTT = /wtt finals|wtt grand smash|wtt champions|grand smash|europe smash/i;

const NATIONAL_CHAMP =
  /swedish championship|german championship|french championship|english championship|japanese championship|chinese championship|national championship|national championships|campeonato nacional/i;

const NATIONAL_COUNTRY_FROM_EVENT: Array<[RegExp, string]> = [
  [/swedish/i, "Suécia"],
  [/german/i, "Alemanha"],
  [/french/i, "França"],
  [/english|british/i, "Inglaterra"],
  [/japanese/i, "Japão"],
  [/chinese/i, "China"],
  [/brazilian|brasileiro/i, "Brasil"],
];

const SECTION_COMP_ALIASES: Array<[RegExp, string]> = [
  [/wtt grand smash|\bgrand smash\b/i, "WTT Grand Smash"],
  [/wtt champions|\bwtt champion\b/i, "WTT Champions"],
  [/wtt finals|cup finals|year-end finals/i, "WTT Finals"],
  [/table tennis world cup|ittf world cup|\bworld cup\b/i, "Copa do Mundo"],
  [/star contender/i, "WTT Star Contender"],
  [/\bcontender\b/i, "WTT Contender"],
];

const LOCATION_PT: Record<string, string> = {
  Singapore: "Singapura",
  Macau: "Macau",
  Macao: "Macau",
  "Hong Kong": "Hong Kong",
  "United States": "Estados Unidos",
  China: "China",
  Doha: "Doha",
  "Buenos Aires": "Buenos Aires",
  "Foz do Iguaçu": "Foz do Iguaçu",
  "Rock Hill": "Rock Hill",
  Malmö: "Malmö",
  Malmo: "Malmö",
  Montpellier: "Montpellier",
  Saudi: "Arábia Saudita",
};

function locationLookupKeys(location: string): string[] {
  const keys = [location];
  for (const [source, target] of Object.entries(LOCATION_PT)) {
    if (location === target) keys.push(source);
    else if (location === source) keys.push(target);
  }
  return keys;
}

function sectionCompetitionName(sectionRaw: string): string | null {
  const cleaned = cleanWikiText(sectionRaw);
  for (const [pattern, name] of SECTION_COMP_ALIASES) {
    if (pattern.test(cleaned)) return name;
  }
  return null;
}

function isWorldCupMedal(
  year: string | null,
  location: string,
  combined: string,
  sectionComp: string | null,
): boolean {
  if (year === "2025" && (location === "Macau" || location === "Macao")) {
    if (/mixed team|equipe/i.test(combined)) return true;
    return false;
  }
  if (/table tennis world cup|ittf world cup|mixed team world cup/i.test(combined)) {
    return true;
  }
  if (sectionComp === "Copa do Mundo") return true;
  if (year === "2026" && (location === "Macau" || location === "Macao")) return true;
  return false;
}

function isInvalidMacau2025Singles(
  year: string | null,
  location: string,
  category: string,
  raw: string,
): boolean {
  if (year !== "2025" || category !== "Simples") return false;
  const loc = location.toLowerCase();
  if (!loc.includes("macau") && !loc.includes("macao")) return false;
  if (/mixed team|equipe/i.test(raw)) return false;
  return true;
}

function defaultLocationForEvent(
  compName: string,
  year: string | null,
  eventRaw = "",
): string {
  const lower = eventRaw.toLowerCase();
  const tokens: Array<[string, string]> = [
    ["macao", "Macau"],
    ["macau", "Macau"],
    ["singapore", "Singapura"],
    ["montpellier", "Montpellier"],
    ["malmö", "Malmö"],
    ["malmo", "Malmö"],
    ["europe smash", "Malmö"],
    ["saudi", "Arábia Saudita"],
    ["united states", "Estados Unidos"],
    ["china smash", "China"],
    ["chongqing", "Chongqing"],
    ["incheon", "Incheon"],
    ["yokohama", "Yokohama"],
  ];
  for (const [token, loc] of tokens) {
    if (lower.includes(token)) return loc;
  }
  if (compName === "WTT Finals" && year) {
    return WTT_FINALS_DEFAULT_LOCATION[year] ?? "Hong Kong";
  }
  if (year && year !== "?") {
    for (const locKey of Object.keys(LOCATION_PT)) {
      if (MEDAL_LOCATION_EVENT[medalLocationEventKey(year, locKey)] === compName) {
        return localizePlace(locKey);
      }
    }
  }
  return "?";
}

function extractEventLocationFromName(event: string): [string, string | null] {
  const lower = cleanWikiText(event).toLowerCase();
  const comp = normalizeEventName(event);
  const tokens: Array<[string, string]> = [
    ["montpellier", "Montpellier"],
    ["malmö", "Malmö"],
    ["malmo", "Malmö"],
    ["europe smash", "Malmö"],
    ["macao", "Macau"],
    ["macau", "Macau"],
    ["singapore", "Singapura"],
    ["incheon", "Incheon"],
  ];
  for (const [token, loc] of tokens) {
    if (lower.includes(token)) return [comp, localizePlace(loc)];
  }
  return [comp, null];
}

function medalLocationEventKey(year: string, loc: string): string {
  return `${year}|${loc}`;
}

export function translateHighlight(text: string): string {
  let out = text.replace("Champions", "\x00CHAMPIONS\x00");
  out = out.replace(/\bChampion\b/g, "Campeão");
  out = out.replace("\x00CHAMPIONS\x00", "Champions");

  const replacements: Array<[string, string]> = [
    ["World Table Tennis Championships", "Campeonato Mundial"],
    ["World Championships", "Campeonato Mundial"],
    ["World Team Table Tennis Championships", "Campeonato Mundial"],
    ["Table Tennis World Cup", "Copa do Mundo"],
    ["Pan American Table Tennis Championships", "Pan-Americano"],
    ["Pan American Games", "Jogos Pan-Americanos"],
    ["Olympic Games", "Olimpíadas"],
    ["Singles titles:", "Títulos em simples:"],
    ["Doubles titles:", "Títulos em duplas:"],
    ["Career titles:", "Títulos na carreira:"],
    [" singles:", " simples:"],
    [" doubles:", " duplas:"],
    [" mixed:", " mista:"],
    ["Mixed doubles", "Duplas mistas"],
    ["Mixed team", "Equipe mista"],
    ["Men's singles", "Simples"],
    ["Women's singles", "Simples"],
    ["Men's doubles", "Duplas"],
    ["Women's doubles", "Duplas"],
    ["Men's team", "Equipe"],
    ["Women's team", "Equipe"],
    ["Singles", "Simples"],
    ["Doubles", "Duplas"],
    ["Team", "Equipe"],
    ["World Campeonato Mundial", "Campeonato Mundial"],
    ["World Championship", "Campeonato Mundial"],
    ["World Campeãoship", "Campeonato Mundial"],
    ["Winner", "Campeão"],
    ["Gold", "Ouro"],
    ["Silver", "Prata"],
    ["Bronze", "Bronze"],
  ];
  for (const [source, target] of replacements) {
    out = out.replaceAll(source, target);
  }
  return out;
}

export function cleanWikiText(value: string): string {
  let text = value;
  text = text.replace(WIKI_REF, "");
  text = text.replace(WIKI_TEMPLATE, "");
  text = text.replace(WIKI_LINK, "$2");
  text = text.replace(WIKI_EXT_LINK, (_, label) => (label ?? "").trim());
  text = text.replace(WIKI_BOLD, "$1");
  text = text.replace(/<[^>]+>/g, "");
  text = text.replace(RAW_URL, "");
  text = text.replace(/\{\{CHN\}\}/g, "China");
  text = text.replace(/\{\{chn\}\}/g, "China");
  text = text.replace(/\(\s*archived[^)]*\)/gi, "");
  text = text.replace(/\(\s*alternate link[^)]*\)/gi, "");
  text = text.replace(/[\[\]]/g, "");
  text = text.replace(/\s+/g, " ").trim().replace(/[ .,;]+$/g, "");
  return text;
}

function localizePlace(text: string): string {
  let out = text;
  for (const [source, target] of Object.entries(LOCATION_PT)) {
    out = out.replace(new RegExp(`\\b${escapeRegExp(source)}\\b`, "g"), target);
  }
  return out;
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
}

export function yearFromParts(...parts: string[]): string | null {
  for (const part of parts) {
    if (!part) continue;
    const match = part.match(YEAR_IN_TEXT);
    if (match) return match[0];
  }
  return null;
}

function disciplineToPt(value: string): string {
  const lower = cleanWikiText(value).toLowerCase();
  if (lower.includes("mixed doubles") || lower === "mixed") return "Duplas mistas";
  if (lower.includes("mixed team")) return "Equipe mista";
  if (lower.includes("doubles") || lower.includes("duplas")) return "Duplas";
  if (lower.includes("team") || lower.includes("equipe")) return "Equipe";
  if (lower.includes("singles") || lower.includes("simples")) return "Simples";
  return value ? translateHighlight(value) : "Simples";
}

function extractLocation(part1: string, part2: string, year: string | null): string {
  for (const part of [part1, part2]) {
    let loc = cleanWikiText(part);
    if (!loc) continue;
    if (year) loc = loc.replace(new RegExp(`^${escapeRegExp(year)}\\s*`), "").trim();
    loc = loc.replace(/^\d{4}\s*/, "").trim();
    const lower = loc.toLowerCase();
    if (
      ["singles", "doubles", "mixed doubles", "team", "mixed team", "simples", "duplas", "equipe"]
        .includes(lower)
    ) {
      continue;
    }
    if (loc) return localizePlace(loc);
  }
  return "?";
}

function resolveCompetitionName(
  part1: string,
  part2: string,
  raw: string,
  year: string | null,
  location: string,
  sectionComp: string | null = null,
): string {
  const combined = `${part1} ${part2} ${raw}`;

  if (sectionComp && sectionComp !== "Copa do Mundo") return sectionComp;
  if (isWorldCupMedal(year, location, combined, sectionComp)) return "Copa do Mundo";

  for (const [pattern, name] of COMPETITION_ALIASES) {
    if (pattern.test(combined)) return name;
  }

  if (year && location !== "?") {
    for (const loc of locationLookupKeys(location)) {
      const mapped = MEDAL_LOCATION_EVENT[medalLocationEventKey(year, loc)];
      if (mapped) return mapped;
    }
  }

  const lower = combined.toLowerCase();
  if (lower.includes("europe smash") || (lower.includes("grand smash") && lower.includes("smash"))) {
    return "WTT Grand Smash";
  }
  if (lower.includes("grand smash") || /\bsmash\b/i.test(lower)) return "WTT Grand Smash";
  if (lower.includes("star contender")) return "WTT Star Contender";
  if (lower.includes("contender")) return "WTT Contender";
  if (lower.includes("wtt champions")) return "WTT Champions";
  if (lower.includes("cup finals") || lower.includes("wtt finals")) return "WTT Finals";
  if (sectionComp) return sectionComp;
  if (WTT_EVENT.test(combined)) return formatWttEventName(part1 || part2);

  const cleaned = translateHighlight(cleanWikiText(part1 || part2));
  return cleaned || "Torneio";
}

function formatMedalLine(
  medalPlace: string,
  params: string[],
  sectionComp: string | null = null,
): string | null {
  const normalized =
    medalPlace.charAt(0).toUpperCase() + medalPlace.slice(1).toLowerCase();
  let resultPt = RESULT_PT[normalized];
  if (!resultPt) return null;

  const part1 = params[0] ? cleanWikiText(params[0]) : "";
  const part2 = params.length > 1 ? cleanWikiText(params[1]) : "";
  const raw = params.join(" ");
  const year = yearFromParts(part1, part2, raw) ?? "?";
  const location = extractLocation(part1, part2, year);
  const category = disciplineToPt(part2 || part1);
  const compName = resolveCompetitionName(part1, part2, raw, year, location, sectionComp);

  if (isInvalidMacau2025Singles(year, location, category, raw)) {
    if (
      sectionComp === "Copa do Mundo" ||
      /table tennis world cup|ittf world cup/i.test(raw)
    ) {
      return null;
    }
  }

  if (
    compName === "WTT Finals" &&
    normalized === "Bronze" &&
    year === "2025" &&
    location === "Hong Kong" &&
    category === "Simples" &&
    sectionComp === "WTT Finals"
  ) {
    resultPt = "Campeão";
  }

  if (PARTICIPATION_ONLY.test(raw) && resultPt !== "Campeão") return null;
  if (
    resultPt !== "Campeão" &&
    WTT_EVENT.test(compName) &&
    normalized !== "Gold" &&
    !PRESTIGIOUS_WTT.test(compName)
  ) {
    return null;
  }

  let resolvedLocation = location;
  if (
    resolvedLocation === "?" &&
    ["WTT Finals", "WTT Grand Smash", "WTT Champions"].includes(compName)
  ) {
    resolvedLocation = defaultLocationForEvent(compName, year, part1 || part2);
  }

  const locationYear = `${resolvedLocation} ${year}`.trim();
  return `${compName}: ${resultPt} (${locationYear} — ${category})`;
}

export function titleCategory(title: string): string {
  const lower = title.toLowerCase();
  if (lower.startsWith("nacional:")) return "nacional";
  if (WTT_EVENT.test(lower)) return "wtt";
  if (
    NACIONAL_EVENT.test(lower) ||
    /\b(lima|santiago|havana|guaynabo|asunción|cartagena|san juan|toronto|santo domingo|rock hill|san salvador|suécia|suecia|sweden)\b/i
      .test(lower)
  ) {
    return "nacional";
  }
  return "outros";
}

function splitTournamentList(value: string): string[] {
  return value.split(/,\s*|\t|\n/).map((p) => p.trim()).filter(Boolean);
}

function splitWikiParams(text: string): string[] {
  const parts: string[] = [];
  let current = "";
  let linkDepth = 0;
  for (const ch of text) {
    if (ch === "[") linkDepth++;
    else if (ch === "]") linkDepth = Math.max(0, linkDepth - 1);
    else if (ch === "|" && linkDepth === 0) {
      parts.push(current);
      current = "";
      continue;
    }
    current += ch;
  }
  parts.push(current);
  return parts;
}

function extractMedalsWithContext(
  wikitext: string,
): Array<[string | null, string, string[]]> {
  const results: Array<[string | null, string, string[]]> = [];
  let currentSection: string | null = null;
  const compRe = /\{\{MedalCompetition\|([^{}]+)\}\}/gi;
  const opener = /\{\{(Medal(?:Gold|Silver|Bronze))\|/gi;

  let pos = 0;
  while (pos < wikitext.length) {
    compRe.lastIndex = pos;
    opener.lastIndex = pos;
    const compM = compRe.exec(wikitext);
    const medalM = opener.exec(wikitext);
    if (!compM && !medalM) break;

    if (compM && (!medalM || compM.index <= medalM.index)) {
      currentSection = sectionCompetitionName(compM[1]);
      pos = compM.index + compM[0].length;
      continue;
    }

    if (!medalM) break;
    let depth = 2;
    let i = medalM.index + medalM[0].length;
    let content = "";
    while (i < wikitext.length) {
      if (wikitext.startsWith("{{", i)) {
        depth += 2;
        content += "{{";
        i += 2;
        continue;
      }
      if (wikitext.startsWith("}}", i)) {
        depth -= 2;
        if (depth === 0) break;
        content += "}}";
        i += 2;
        continue;
      }
      content += wikitext[i++];
    }
    const place = medalM[1].replace(/^Medal/i, "");
    results.push([currentSection, place, splitWikiParams(content)]);
    pos = i + 2;
  }
  return results;
}

function formatWttEventName(event: string): string {
  let cleaned = cleanWikiText(event);
  cleaned = translateHighlight(cleaned);
  const lower = cleaned.toLowerCase();
  if (lower.includes("grand smash")) return "WTT Grand Smash";
  if (lower.includes("europe smash")) return "WTT Grand Smash";
  if (lower.includes("star contender")) return "WTT Star Contender";
  if (lower.includes("contender")) return "WTT Contender";
  if (lower.includes("cup finals") || lower.includes("wtt finals")) return "WTT Finals";
  if (lower.includes("wtt champions") || /\bwtt\b.*\bchampions\b/i.test(lower)) {
    return "WTT Champions";
  }
  if (lower.includes("world cup") && lower.includes("table tennis")) return "Copa do Mundo";
  if (lower.startsWith("wtt ")) return cleaned;
  if (WTT_EVENT.test(cleaned)) {
    return cleaned.toUpperCase().startsWith("WTT") ? cleaned : `WTT ${cleaned}`;
  }
  return cleaned;
}

function normalizeEventName(event: string): string {
  let cleaned = cleanWikiText(event);
  if (/pan.?american.*championship/i.test(cleaned)) return "Pan-Americano";
  if (/table tennis world cup|ittf world cup/i.test(cleaned)) {
    if (yearFromParts(cleaned) === "2025" && /macao|macau/i.test(cleaned)) {
      return "WTT Champions";
    }
    return "Copa do Mundo";
  }
  if (/world table tennis championship/i.test(cleaned)) return "Campeonato Mundial";
  if (/olympic/i.test(cleaned)) return "Olimpíadas";
  if (/pan american games/i.test(cleaned)) return "Jogos Pan-Americanos";
  const lower = cleaned.toLowerCase();
  if (lower.includes("europe smash") || /\b\w+\s+smash\b/i.test(lower)) {
    return "WTT Grand Smash";
  }
  cleaned = translateHighlight(cleaned);
  if (WTT_EVENT.test(cleaned)) return formatWttEventName(cleaned);
  return cleaned;
}

function expandParentheticalEntries(details: string): string[] {
  const cleaned = localizePlace(cleanWikiText(details));
  const entries: string[] = [];
  for (const chunk of splitTournamentList(cleaned)) {
    const trimmed = chunk.trim();
    if (!trimmed) continue;
    const year = yearFromParts(trimmed);
    if (year && /^\d+$/.test(trimmed)) {
      entries.push(year);
      continue;
    }
    entries.push(trimmed);
  }
  return entries;
}

function inferBulletCategory(event: string, detail: string): string | null {
  const lower = detail.toLowerCase();
  if (lower.includes("mixed") || lower.includes("mista")) return "Duplas mistas";
  if (lower.includes("doubles") || lower.includes("duplas")) return "Duplas";
  const eventLower = event.toLowerCase();
  if (eventLower.includes("mixed doubles")) return "Duplas mistas";
  if (eventLower.includes("singles") || eventLower.includes("simples")) return "Simples";
  return null;
}

function resultToPt(result: string, event: string): string | null {
  const cleaned = cleanWikiText(result);
  if (!cleaned || PARTICIPATION_ONLY.test(cleaned)) return null;

  const important = IMPORTANT_COMP.test(event);
  const wtt = WTT_EVENT.test(event);
  const prestigious = PRESTIGIOUS_WTT.test(event);

  if (TITLE_RESULT.test(cleaned)) return "Campeão";
  if (RUNNER_UP.test(cleaned)) {
    if (important && !wtt) return "2° lugar";
    if (prestigious || /wtt finals|grand smash|europe smash|wtt champions/i.test(event)) {
      return "2° lugar";
    }
    return null;
  }
  if (BRONZE_RESULT.test(cleaned)) {
    if (important && !wtt) return "3° lugar";
    if (prestigious) return "3° lugar";
    return null;
  }
  if (SEMIFINAL.test(cleaned)) return important || prestigious ? "4° lugar" : null;
  if (QUARTERFINAL.test(cleaned)) return important ? "5-8° lugar" : null;
  return null;
}

function formatNationalBullet(
  event: string,
  resultPt: string,
  detail: string,
): string | null {
  let country: string | null = null;
  for (const [pattern, ptCountry] of NATIONAL_COUNTRY_FROM_EVENT) {
    if (pattern.test(event)) {
      country = ptCountry;
      break;
    }
  }
  if (!country) return null;
  const year = yearFromParts(detail) ?? "?";
  const category = inferBulletCategory(event, detail) ?? "Simples";
  return `Nacional: ${resultPt} (${country} ${year} — ${category})`;
}

function formatBulletTitle(
  event: string,
  resultPt: string,
  detail: string,
): string | null {
  if (NATIONAL_CHAMP.test(event)) {
    return formatNationalBullet(event, resultPt, detail);
  }

  const [eventName, eventLoc] = extractEventLocationFromName(event);
  const detailClean = localizePlace(cleanWikiText(detail));
  let year = yearFromParts(detailClean) ?? "?";
  let category = inferBulletCategory(event, detailClean) ?? "Simples";
  const locCheck =
    eventLoc ??
    (year !== "?" ? detailClean.replace(year, "", 1).trim() : detailClean);
  if (isInvalidMacau2025Singles(year, locCheck, category, `${eventName} ${detailClean}`)) {
    if (eventName === "Copa do Mundo") return null;
  }

  const cleanedDetail = detailClean;
  year = yearFromParts(cleanedDetail) ?? "?";
  const remainder = year !== "?"
    ? (() => {
      const idx = cleanedDetail.indexOf(year);
      return idx >= 0
        ? (cleanedDetail.slice(0, idx) + cleanedDetail.slice(idx + year.length)).trim()
        : cleanedDetail;
    })()
    : cleanedDetail;
  if (year !== "?" && (!remainder || remainder === year)) {
    if (/pan-americano|campeonato mundial|copa do mundo/i.test(eventName)) return null;
    const location = eventLoc ?? defaultLocationForEvent(eventName, year, event);
    if (location !== "?") {
      category = inferBulletCategory(event, cleanedDetail) ?? "Simples";
      return translateHighlight(
        `${eventName}: ${resultPt} (${location} ${year} — ${category})`,
      );
    }
    return translateHighlight(`${eventName}: ${resultPt} (${year})`);
  }
  const location = localizePlace(remainder) || eventLoc || cleanedDetail || year;
  category = inferBulletCategory(event, cleanedDetail);
  const line = category
    ? `${eventName}: ${resultPt} (${location} ${year} — ${category})`
    : `${eventName}: ${resultPt} (${location} ${year})`;
  return translateHighlight(line);
}

function isRelevantWikiEvent(event: string): boolean {
  const cleaned = cleanWikiText(event);
  return (
    WTT_EVENT.test(cleaned) ||
    IMPORTANT_COMP.test(cleaned) ||
    NACIONAL_EVENT.test(cleaned) ||
    NATIONAL_CHAMP.test(cleaned) ||
    /pan.?american|world cup|grand smash|smash|contender|olympic|mundial|europe smash/i.test(
      cleaned,
    )
  );
}

function splitBulletEventRest(body: string): [string | null, string | null] {
  if (body.includes(":")) {
    const idx = body.indexOf(":");
    return [body.slice(0, idx).trim(), body.slice(idx + 1).trim()];
  }
  const dash = body.match(/\s[-–—]\s/);
  if (dash && dash.index != null) {
    return [body.slice(0, dash.index).trim(), body.slice(dash.index + dash[0].length).trim()];
  }
  return [null, null];
}

function parseWikiBulletLine(line: string): string[] {
  const stripped = line.trim();
  if (!stripped.startsWith("*")) return [];
  if (
    stripped.startsWith("* {") ||
    stripped.startsWith("* {{") ||
    stripped.startsWith("* [")
  ) {
    return [];
  }

  let body = stripped.replace(/^\*\s*/, "").trim();
  body = body.replace(WIKI_REF, "");
  body = cleanWikiText(body);
  if (!body || RAW_URL.test(body) || JUNK_TEXT.test(body)) return [];
  const [event, rest] = splitBulletEventRest(body);
  if (!event || !rest) return [];
  if (!isRelevantWikiEvent(event) && !NATIONAL_CHAMP.test(event)) return [];

  const parenMatch = rest.match(/\(([^)]+)\)/);
  if (!parenMatch || parenMatch.index == null) return [];

  const detailsRaw = parenMatch[1];
  const resultRaw = rest.slice(0, parenMatch.index).trim().replace(/[ .]+$/g, "");
  const resultPt = resultToPt(resultRaw, event);
  if (!resultPt) return [];

  const titles: string[] = [];
  for (const detail of expandParentheticalEntries(detailsRaw)) {
    const formatted = formatBulletTitle(event, resultPt, detail);
    if (formatted) titles.push(formatted);
  }
  return titles;
}

function formatTableWinnerTitle(
  eventRaw: string,
  year: string,
  defaultCategory = "Simples",
): string | null {
  const category = inferBulletCategory(eventRaw, eventRaw) ?? defaultCategory;
  const [, eventLoc] = extractEventLocationFromName(eventRaw);
  const compGuess = normalizeEventName(eventRaw);
  let location = eventLoc ?? defaultLocationForEvent(compGuess, year, eventRaw);
  if (location === "?") {
    location = extractLocation(eventRaw, "", year);
  }
  const compName = resolveCompetitionName(eventRaw, "", eventRaw, year, location);
  if (
    location === "?" &&
    ["WTT Finals", "WTT Grand Smash", "WTT Champions"].includes(compName)
  ) {
    location = defaultLocationForEvent(compName, year, eventRaw);
  }
  if (
    year === "2025" &&
    (location === "Macau" || location === "Macao") &&
    compName === "Copa do Mundo" &&
    category === "Simples"
  ) {
    return `WTT Champions: Campeão (${location} ${year} — ${category})`;
  }
  if (isInvalidMacau2025Singles(year, location, category, eventRaw)) {
    if (compName === "Copa do Mundo") {
      return `WTT Champions: Campeão (${location !== "?" ? `${location} ${year}` : year} — ${category})`;
    }
  }
  if (location !== "?") {
    return `${compName}: Campeão (${location} ${year} — ${category})`;
  }
  return `${compName}: Campeão (${year} — ${category})`;
}

function isInvalidMacau2025WorldCupTitle(text: string): boolean {
  const lower = text.toLowerCase();
  return (
    lower.includes("copa do mundo") &&
    lower.includes("macau") &&
    lower.includes("2025") &&
    lower.includes("simples")
  );
}

function parseNotableResultsTable(wikitext: string): string[] {
  const titles: string[] = [];
  let currentYear: string | null = null;

  for (const line of wikitext.split("\n")) {
    const rowSpan = line.match(/rowspan="\d+"\|(\d{4})/);
    if (rowSpan) currentYear = rowSpan[1];
    if (!currentYear) continue;
    if (!line.trim().startsWith("|-") && !rowSpan) continue;

    const cells = line
      .split("|")
      .map((c) => cleanWikiText(c.trim()))
      .filter((c) => c && c !== "-" && !c.startsWith('rowspan="'));
    let eventRaw = "";
    if (rowSpan && cells.length >= 2) {
      eventRaw = cells[0] === currentYear ? cells[1] : cells[0];
    } else if (line.trim().startsWith("|-") && cells.length >= 1) {
      eventRaw = cells[0];
    } else {
      continue;
    }

    if (!eventRaw || !isRelevantWikiEvent(eventRaw) || PARTICIPATION_ONLY.test(eventRaw)) {
      continue;
    }
    const formatted = formatTableWinnerTitle(eventRaw, currentYear);
    if (formatted) titles.push(formatted);
  }
  return titles;
}

function parseSinglesTitlesTable(wikitext: string): string[] {
  const titles: string[] = [];
  let inTable = false;
  let currentYear: string | null = null;

  for (const line of wikitext.split("\n")) {
    if (line.includes("==Singles titles==")) {
      inTable = true;
      continue;
    }
    if (inTable && line.startsWith("==") && !line.includes("Singles titles")) break;
    if (!inTable) continue;

    const rowSpan = line.match(/rowspan="\d+"\|(\d{4})/);
    if (rowSpan) currentYear = rowSpan[1];

    const stripped = line.trim();
    if (!stripped.startsWith("|") || stripped === "|-" || stripped === "|}") continue;

    const cells = stripped
      .split("|")
      .map((c) => cleanWikiText(c.trim()))
      .filter((c) => c && c !== "-" && !c.startsWith('rowspan="'));
    if (!cells.length) continue;

    let eventRaw = "";
    if (/^\d{4}$/.test(cells[0])) {
      currentYear = cells[0];
      if (cells.length < 2) continue;
      eventRaw = cells[1];
    } else if (currentYear) {
      eventRaw = cells[0];
    } else {
      continue;
    }

    if (!eventRaw || /^\d{4}$/.test(eventRaw)) continue;
    if (/final opponent|score|ref|tournament/i.test(eventRaw)) continue;
    if (!isRelevantWikiEvent(eventRaw) && !WTT_EVENT.test(eventRaw)) continue;

    const formatted = formatTableWinnerTitle(eventRaw, currentYear);
    if (formatted) titles.push(formatted);
  }
  return titles;
}

function parseWikiProseTitles(wikitext: string): string[] {
  const plain = cleanWikiText(wikitext.replace(WIKI_REF, ""));
  const titles: string[] = [];

  if (
    /WTT Contender in Buenos Aires.*mixed doubles.*(?:Bruna Takahashi|Takahashi)/is.test(
      plain,
    )
  ) {
    titles.push("WTT Contender: Campeão (Buenos Aires 2025 — Duplas mistas)");
  }

  if (
    /Pan American Table Tennis Championships champion.*mixed doubles.*(?:Bruna Takahashi|Takahashi)/is
      .test(plain)
  ) {
    titles.push("Pan-Americano: Campeão (Rock Hill 2025 — Duplas mistas)");
  }

  const finalsYears = plain.match(
    /won the men's singles title at the WTT Finals in ((?:\d{4},?\s*(?:and\s*)?)+)/i,
  );
  if (finalsYears) {
    for (const year of finalsYears[1].match(/\d{4}/g) ?? []) {
      const loc = WTT_FINALS_DEFAULT_LOCATION[year] ?? "Hong Kong";
      titles.push(`WTT Finals: Campeão (${loc} ${year} — Simples)`);
    }
  }

  titles.push(...parseNotableResultsTable(wikitext));
  titles.push(...parseSinglesTitlesTable(wikitext));
  return titles;
}

function isGenericCardHighlight(value: string): boolean {
  return GENERIC_CARD_MARKERS.some((marker) => value.includes(marker));
}

export function titlesFromCard(card: Record<string, unknown>): string[] {
  const titles: string[] = [];

  const singles = card.singles_titles;
  const doubles = card.doubles_titles;
  if (singles) titles.push(translateHighlight(`Singles titles: ${singles}`));
  if (doubles) titles.push(translateHighlight(`Doubles titles: ${doubles}`));

  const statsRaw = card.stats;
  if (statsRaw) {
    try {
      const stats = typeof statsRaw === "string" ? JSON.parse(statsRaw) : statsRaw;
      const careerTitles = stats.career_titles ?? stats.tournament_wins;
      if (careerTitles) {
        titles.push(translateHighlight(`Career titles: ${careerTitles}`));
      }
    } catch {
      /* ignore */
    }
  }

  return titles;
}

function isJunkTitle(text: string): boolean {
  if (!text) return true;
  if (RAW_URL.test(text) || text.includes("{{") || /\[http/i.test(text)) return true;
  if (JUNK_TEXT.test(text)) return true;
  if (text.startsWith("Último resultado:")) return true;
  if (/^\d{4}\s+(Ouro|Prata|Bronze)\s+—/.test(text)) return true;
  if (text.startsWith("WTT Star Contender: Campeão") && !text.includes("(")) return true;
  if (PARTICIPATION_ONLY.test(text) && !/campeão|2° lugar/i.test(text)) return true;
  return false;
}

function normalizeIdentityEvent(event: string): string {
  const lower = event.toLowerCase();
  if (lower.startsWith("nacional")) return "nacional";
  if (lower.includes("campeonato mundial") || lower.includes("world table tennis")) {
    return "campeonato mundial";
  }
  if (lower.includes("pan-americano") || lower.includes("pan american")) {
    return "pan-americano";
  }
  if (lower.includes("copa do mundo") || lower.includes("world cup")) {
    return "copa do mundo";
  }
  if (lower.includes("wtt grand smash") || lower.includes("grand smash") || lower.includes("europe smash")) {
    return "wtt grand smash";
  }
  if (lower.includes("wtt finals") || lower.includes("cup finals")) {
    return "wtt finals";
  }
  if (lower.includes("wtt star contender")) return "wtt star contender";
  if (lower.includes("wtt contender")) return "wtt contender";
  if (lower.includes("wtt champions")) return "wtt champions";
  return lower;
}

type TitleIdentity = [string, string, string, string];

function titleIdentity(title: string): TitleIdentity {
  const year = yearFromParts(title) ?? "";
  const lower = title.toLowerCase();
  let category = "simples";
  if (lower.includes("duplas mistas") || lower.includes("— mista")) category = "mista";
  else if (lower.includes("duplas")) category = "duplas";
  else if (lower.includes("equipe")) category = "equipe";
  else if (lower.includes("simples")) category = "simples";

  const rawEvent = title.includes(":")
    ? title.slice(0, title.indexOf(":")).trim()
    : title;
  const event = normalizeIdentityEvent(rawEvent);
  let location = "";
  const paren = title.match(/\(([^)]+)\)/);
  if (paren) {
    let inner = paren[1].toLowerCase();
    inner = inner.replace(YEAR_IN_TEXT, "").split("—")[0].trim();
    location = inner.replace(/\s+/g, " ").trim().replace(/[, ]+$/g, "");
  }
  return [event, year, location, category];
}

function titlePriority(title: string): number {
  const lower = title.toLowerCase();
  if (lower.includes("campeão") || lower.includes("campeã")) return 4;
  if (lower.includes("2° lugar") || lower.includes("prata")) return 3;
  if (lower.includes("3° lugar") || lower.includes("bronze")) return 2;
  if (lower.includes("4° lugar") || lower.includes("5-8")) return 1;
  return 0;
}

export function mergeTitles(...sources: string[][]): string[] {
  const best = new Map<TitleIdentity, [number, string]>();
  const order: TitleIdentity[] = [];

  for (const source of sources) {
    for (const raw of source) {
      let text = translateHighlight(cleanWikiText(raw.trim()));
      if (isJunkTitle(text)) continue;
      if (isGenericCardHighlight(text)) continue;
      if (isInvalidMacau2025WorldCupTitle(text)) {
        text = text.replace(/^Copa do Mundo:/, "WTT Champions:");
      }

      const key = titleIdentity(text);
      const priority = titlePriority(text);
      const existing = best.get(key);
      if (!existing) {
        order.push(key);
        best.set(key, [priority, text]);
      } else if (priority > existing[0]) {
        best.set(key, [priority, text]);
      }
    }
  }

  const seenText = new Set<string>();
  const merged: string[] = [];
  for (const key of order) {
    const entry = best.get(key);
    if (!entry) continue;
    const text = entry[1];
    if (seenText.has(text)) continue;
    seenText.add(text);
    merged.push(text);
  }
  return merged;
}

export function sortTitlesByYear(titles: string[]): string[] {
  const sortKey = (title: string): [number, string] => {
    const year = yearFromParts(title) ?? "0000";
    return [/^\d+$/.test(year) ? Number.parseInt(year, 10) : 0, title];
  };

  const summary = titles.filter(
    (t) => t.includes("Títulos em") || t.includes("Títulos na carreira"),
  );
  const rest = titles.filter((t) => !summary.includes(t));
  rest.sort((a, b) => {
    const [ya, ta] = sortKey(a);
    const [yb, tb] = sortKey(b);
    return yb - ya || ta.localeCompare(tb);
  });
  return [...summary, ...rest];
}

async function wikiPageTitle(playerName: string): Promise<string | null> {
  const searchUrl = new URL("https://en.wikipedia.org/w/api.php");
  searchUrl.searchParams.set("action", "query");
  searchUrl.searchParams.set("list", "search");
  searchUrl.searchParams.set("srsearch", `${playerName} table tennis`);
  searchUrl.searchParams.set("srlimit", "5");
  searchUrl.searchParams.set("format", "json");

  const searchResp = await fetch(searchUrl, { headers: WIKI_HEADERS });
  if (!searchResp.ok) return null;
  const hits = (await searchResp.json())?.query?.search ?? [];
  if (!hits.length) return null;

  const family = playerName.split(" ").pop()?.toLowerCase() ?? "";
  for (const hit of hits) {
    const title = String(hit.title ?? "");
    if (family && title.toLowerCase().includes(family)) return title;
  }
  return String(hits[0].title);
}

async function titlesFromWikipedia(playerName: string): Promise<string[]> {
  const titles: string[] = [];
  try {
    const page = await wikiPageTitle(playerName);
    if (!page) return titles;

    const parseUrl = new URL("https://en.wikipedia.org/w/api.php");
    parseUrl.searchParams.set("action", "parse");
    parseUrl.searchParams.set("page", page);
    parseUrl.searchParams.set("prop", "wikitext");
    parseUrl.searchParams.set("format", "json");

    const parseResp = await fetch(parseUrl, { headers: WIKI_HEADERS });
    if (!parseResp.ok) return titles;
    const wikitext = (await parseResp.json())?.parse?.wikitext?.["*"] as
      | string
      | undefined;
    if (!wikitext) return titles;

    for (const [sectionComp, medalPlace, params] of extractMedalsWithContext(wikitext)) {
      const formatted = formatMedalLine(medalPlace, params, sectionComp);
      if (formatted) titles.push(formatted);
    }

    for (const line of wikitext.split("\n")) {
      titles.push(...parseWikiBulletLine(line));
    }

    titles.push(...parseWikiProseTitles(wikitext));
  } catch {
    /* ignore network errors */
  }
  return titles;
}

export async function buildChampionships(
  card: Record<string, unknown>,
  playerName: string,
): Promise<string[]> {
  const cardTitles = titlesFromCard(card);
  const wikiTitles = await titlesFromWikipedia(playerName);
  return sortTitlesByYear(mergeTitles(cardTitles, wikiTitles));
}
