const WIKI_HEADERS = { "User-Agent": "TM-Val/1.0 (tm-val-app)" };

export type WikiLang = "en" | "pt";

export function wikiApiBase(lang: WikiLang): string {
  return `https://${lang}.wikipedia.org/w/api.php`;
}

export async function wikiPageTitle(
  playerName: string,
  lang: WikiLang = "en",
): Promise<string | null> {
  const family = playerName.split(" ").pop()?.toLowerCase() ?? "";
  const queries = lang === "pt"
    ? [`${playerName} tênis de mesa`, playerName, `${playerName} table tennis`]
    : [`${playerName} table tennis`, playerName, `${playerName} tênis de mesa`];
  for (const query of queries) {
    const searchUrl = new URL(wikiApiBase(lang));
    searchUrl.searchParams.set("action", "query");
    searchUrl.searchParams.set("list", "search");
    searchUrl.searchParams.set("srsearch", query);
    searchUrl.searchParams.set("srlimit", "5");
    searchUrl.searchParams.set("format", "json");
    const searchResp = await fetch(searchUrl, { headers: WIKI_HEADERS });
    if (!searchResp.ok) continue;
    const hits = (await searchResp.json())?.query?.search ?? [];
    if (!hits.length) continue;
    for (const hit of hits) {
      const title = String(hit.title ?? "");
      if (family && title.toLowerCase().includes(family)) return title;
    }
    return String(hits[0].title);
  }
  return null;
}

export function mergeTitles(...sources: string[][]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const source of sources) {
    for (const raw of source) {
      const text = String(raw ?? "").trim();
      if (!text || seen.has(text)) continue;
      seen.add(text);
      out.push(text);
    }
  }
  return out;
}

export function sortTitlesByYear(titles: string[]): string[] {
  const yearRe = /\b((?:19|20)\d{2})\b/;
  return [...titles].sort((a, b) => {
    const ya = Number.parseInt(a.match(yearRe)?.[1] ?? "0", 10);
    const yb = Number.parseInt(b.match(yearRe)?.[1] ?? "0", 10);
    return yb - ya || a.localeCompare(b);
  });
}

export async function buildChampionships(
  card: Record<string, unknown>,
  _playerName: string,
): Promise<string[]> {
  const titles: string[] = [];
  const singles = card.singles_titles;
  const doubles = card.doubles_titles;
  if (singles) titles.push(`Títulos em simples: ${singles}`);
  if (doubles) titles.push(`Títulos em duplas: ${doubles}`);
  try {
    const statsRaw = card.stats;
    const stats = typeof statsRaw === "string" ? JSON.parse(statsRaw) : statsRaw;
    const career = stats?.career_titles ?? stats?.tournament_wins;
    if (career) titles.push(`Títulos na carreira: ${career}`);
  } catch {
    /* ignore */
  }
  return sortTitlesByYear(titles);
}

export { WIKI_HEADERS };
