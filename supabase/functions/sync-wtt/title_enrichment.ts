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
  "2025|Singapore": "WTT Champions",
  "2025|Chongqing": "WTT Champions",
  "2025|Macao": "Copa do Mundo",
  "2026|Macao": "Copa do Mundo",
  "2025|Yokohama": "WTT Contender",
  "2025|Hong Kong": "WTT",
  "2026|San Francisco": "Copa das Américas",
  "2025|Doha": "Campeonato Mundial",
  "2026|London": "Campeonato Mundial",
  "2025|Rock Hill": "Pan-Americano",
  "2025|Chengdu": "Copa do Mundo",
  "2025|Bhubaneswar": "Campeonato Asiático",
  "2025|Shenzhen": "Copa Asiática",
  "2026|Haikou": "Copa Asiática",
};

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
};

function locationLookupKeys(location: string): string[] {
  const keys = [location];
  for (const [source, target] of Object.entries(LOCATION_PT)) {
    if (location === target) keys.push(source);
    else if (location === source) keys.push(target);
  }
  return keys;
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
): string {
  const combined = `${part1} ${part2} ${raw}`;
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
  if (lower.includes("grand smash") || /\bsmash\b/i.test(lower)) return "WTT Grand Smash";
  if (lower.includes("star contender")) return "WTT Star Contender";
  if (lower.includes("contender")) return "WTT Contender";
  if (lower.includes("wtt champions")) return "WTT Champions";
  if (lower.includes("cup finals") || lower.includes("wtt finals")) return "WTT Finals";
  if (WTT_EVENT.test(combined)) return formatWttEventName(part1 || part2);

  const cleaned = translateHighlight(cleanWikiText(part1 || part2));
  return cleaned || "Torneio";
}

function formatMedalLine(medalPlace: string, params: string[]): string | null {
  const normalized =
    medalPlace.charAt(0).toUpperCase() + medalPlace.slice(1).toLowerCase();
  const resultPt = RESULT_PT[normalized];
  if (!resultPt) return null;

  const part1 = params[0] ? cleanWikiText(params[0]) : "";
  const part2 = params.length > 1 ? cleanWikiText(params[1]) : "";
  const raw = params.join(" ");
  const year = yearFromParts(part1, part2, raw) ?? "?";
  const location = extractLocation(part1, part2, year);
  const category = disciplineToPt(part2 || part1);
  const compName = resolveCompetitionName(part1, part2, raw, year, location);

  if (PARTICIPATION_ONLY.test(raw) && resultPt !== "Campeão") return null;
  if (resultPt !== "Campeão" && WTT_EVENT.test(compName) && normalized !== "Gold") {
    return null;
  }

  const locationYear = `${location} ${year}`.trim();
  return `${compName}: ${resultPt} (${locationYear} — ${category})`;
}

export function titleCategory(title: string): string {
  const lower = title.toLowerCase();
  if (WTT_EVENT.test(lower)) return "wtt";
  if (
    NACIONAL_EVENT.test(lower) ||
    /\b(lima|santiago|havana|guaynabo|asunción|cartagena|san juan|toronto|santo domingo|rock hill|san salvador)\b/i
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

function extractMedalTemplates(wikitext: string): Array<[string, string[]]> {
  const results: Array<[string, string[]]> = [];
  const opener = /\{\{(Medal(?:Gold|Silver|Bronze))\|/gi;
  let match: RegExpExecArray | null;
  while ((match = opener.exec(wikitext)) !== null) {
    let depth = 2;
    let i = match.index + match[0].length;
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
    const medalType = match[1];
    const place = medalType.replace(/^Medal/i, "");
    results.push([place, splitWikiParams(content)]);
  }
  return results;
}

function formatWttEventName(event: string): string {
  let cleaned = cleanWikiText(event);
  cleaned = translateHighlight(cleaned);
  const lower = cleaned.toLowerCase();
  if (lower.includes("grand smash")) return "WTT Grand Smash";
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
  if (/table tennis world cup/i.test(cleaned)) return "Copa do Mundo";
  if (/world table tennis championship/i.test(cleaned)) return "Campeonato Mundial";
  if (/olympic/i.test(cleaned)) return "Olimpíadas";
  if (/pan american games/i.test(cleaned)) return "Jogos Pan-Americanos";
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

  if (TITLE_RESULT.test(cleaned)) return "Campeão";
  if (RUNNER_UP.test(cleaned)) return important && !wtt ? "2° lugar" : null;
  if (BRONZE_RESULT.test(cleaned)) return important && !wtt ? "3° lugar" : null;
  if (SEMIFINAL.test(cleaned)) return important ? "4° lugar" : null;
  if (QUARTERFINAL.test(cleaned)) return important ? "5-8° lugar" : null;
  return null;
}

function formatBulletTitle(
  event: string,
  resultPt: string,
  detail: string,
): string | null {
  const eventName = normalizeEventName(event);
  const cleanedDetail = localizePlace(cleanWikiText(detail));
  const year = yearFromParts(cleanedDetail) ?? "?";
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
    const line = `${eventName}: ${resultPt} (${year})`;
    return translateHighlight(line);
  }
  const location = remainder || cleanedDetail || year;
  const category = inferBulletCategory(event, cleanedDetail);
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
    /pan.?american|world cup|grand smash|smash|contender|olympic|mundial/i.test(cleaned)
  );
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
  if (!body.includes(":")) return [];

  const colon = body.indexOf(":");
  const event = body.slice(0, colon).trim();
  const rest = body.slice(colon + 1).trim();
  if (!event || !rest || !isRelevantWikiEvent(event)) return [];

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
  return false;
}

function normalizeIdentityEvent(event: string): string {
  const lower = event.toLowerCase();
  if (lower.includes("campeonato mundial") || lower.includes("world table tennis")) {
    return "campeonato mundial";
  }
  if (lower.includes("pan-americano") || lower.includes("pan american")) {
    return "pan-americano";
  }
  if (lower.includes("copa do mundo") || lower.includes("world cup")) {
    return "copa do mundo";
  }
  if (lower.includes("wtt grand smash") || lower.includes("grand smash")) {
    return "wtt grand smash";
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

function mergeTitles(...sources: string[][]): string[] {
  const best = new Map<TitleIdentity, [number, string]>();
  const order: TitleIdentity[] = [];

  for (const source of sources) {
    for (const raw of source) {
      const text = translateHighlight(cleanWikiText(raw.trim()));
      if (isJunkTitle(text)) continue;
      if (isGenericCardHighlight(text)) continue;

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

function sortTitlesByYear(titles: string[]): string[] {
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

    for (const [medalPlace, params] of extractMedalTemplates(wikitext)) {
      const formatted = formatMedalLine(medalPlace, params);
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
