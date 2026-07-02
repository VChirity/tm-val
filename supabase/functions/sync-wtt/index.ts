import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const WTT_HEADERS = {
  Accept: "application/json, text/plain, */*",
  Referer: "https://www.worldtabletennis.com/",
  Origin: "https://www.worldtabletennis.com",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  ApiKey: "2bf8b222-532c-4c60-8ebe-eb6fdfebe84a",
};

const RANKING_URL =
  "https://wtt-web-frontdoor-withoutcache-cqakg0andqf5hchn.a01.azurefd.net/ranking/SEN_SINGLES.json";
const PLAYERS_URL =
  "https://wtt-ttu-connect-frontdoor-g6gwg6e2bgc6gdfm.a01.azurefd.net/Players/GetPlayers";
const PLAYER_CARD_URL =
  "https://wtt-website-api-prod-3-frontdoor-bddnb2haduafdze9.a01.azurefd.net/api/cms/PlayerCard/";

const WIKI_HEADERS = { "User-Agent": "TM-Val/1.0 (tm-val-app)" };

const MEDAL_PT: Record<string, string> = {
  Gold: "Ouro",
  Silver: "Prata",
  Bronze: "Bronze",
};

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function parseInt(value: unknown): number | null {
  if (value == null || value === "") return null;
  const n = Number.parseFloat(String(value));
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function parseFloat(value: unknown): number | null {
  if (value == null || value === "") return null;
  const n = Number.parseFloat(String(value));
  return Number.isFinite(n) ? n : null;
}

function athleteKey(name: string, gender: string) {
  return `${name}|${gender}`;
}

function splitTournamentList(value: string): string[] {
  return value.split(/,\s*|\t|\n/).map((p) => p.trim()).filter(Boolean);
}

function cleanWikiText(value: string): string {
  return value
    .replace(/\[\[[^|\]]+\|([^\]]+)\]\]/g, "$1")
    .replace(/\[\[([^\]]+)\]\]/g, "$1")
    .replace(/<[^>]+>/g, "")
    .replace(/\{\{CHN\}\}/gi, "China")
    .replace(/\s+/g, " ")
    .trim();
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

function extractMedalTemplates(
  wikitext: string,
): Array<{ place: string; params: string[] }> {
  const results: Array<{ place: string; params: string[] }> = [];
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
    results.push({ place, params: splitWikiParams(content) });
  }
  return results;
}

function translateHighlight(text: string): string {
  const replacements: Record<string, string> = {
    "Singles titles:": "Títulos em simples:",
    "Doubles titles:": "Títulos em duplas:",
    "Career titles:": "Títulos na carreira:",
    " singles:": " simples:",
    " doubles:": " duplas:",
    " mixed:": " mista:",
    Winner: "Campeão",
    Champion: "Campeão",
    Team: "Equipe",
    Singles: "Simples",
    Doubles: "Duplas",
    "Mixed doubles": "Duplas mistas",
    "Mixed team": "Equipe mista",
  };
  let out = text;
  for (const [src, dst] of Object.entries(replacements)) {
    out = out.replaceAll(src, dst);
  }
  return out;
}

function titlesFromCard(card: Record<string, unknown>): string[] {
  const titles: string[] = [];
  if (card.singles_titles) titles.push(`Singles titles: ${card.singles_titles}`);
  if (card.doubles_titles) titles.push(`Doubles titles: ${card.doubles_titles}`);

  const statsRaw = card.stats;
  if (statsRaw) {
    try {
      const stats = typeof statsRaw === "string" ? JSON.parse(statsRaw) : statsRaw;
      const career = stats.career_titles ?? stats.tournament_wins;
      if (career) titles.push(`Career titles: ${career}`);
    } catch {
      /* ignore */
    }
  }

  const highlightsRaw = card.highlights;
  if (highlightsRaw) {
    try {
      const highlights = typeof highlightsRaw === "string"
        ? JSON.parse(highlightsRaw)
        : highlightsRaw;
      for (const item of highlights as Record<string, unknown>[]) {
        const year = item.year;
        for (const key of ["singles", "doubles", "mixed"]) {
          const value = item[key];
          if (!value) continue;
          for (const tournament of splitTournamentList(String(value))) {
            titles.push(`${year} ${key}: ${tournament}`);
          }
        }
      }
    } catch {
      /* ignore */
    }
  }

  if (card.result && card.event_name) {
    titles.push(`${card.event_name}: ${card.result}`);
  }
  if (card.last_result) {
    titles.push(`Último resultado: ${card.last_result}`);
  }
  return titles;
}

function extractYear(title: string): number | null {
  const m = title.match(/\b(19|20)\d{2}\b/);
  return m ? Number.parseInt(m[0], 10) : null;
}

function yearFromParts(...parts: string[]): string | null {
  for (const part of parts) {
    if (!part) continue;
    const m = part.match(/\b(19|20)\d{2}\b/);
    if (m) return m[0];
  }
  return null;
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

async function titlesFromWiki(playerName: string): Promise<string[]> {
  if (!playerName.trim()) return [];
  try {
    const page = await wikiPageTitle(playerName);
    if (!page) return [];

    const parseUrl = new URL("https://en.wikipedia.org/w/api.php");
    parseUrl.searchParams.set("action", "parse");
    parseUrl.searchParams.set("page", page);
    parseUrl.searchParams.set("prop", "wikitext");
    parseUrl.searchParams.set("format", "json");

    const parseResp = await fetch(parseUrl, { headers: WIKI_HEADERS });
    if (!parseResp.ok) return [];
    const text = (await parseResp.json())?.parse?.wikitext?.["*"] as
      | string
      | undefined;
    if (!text) return [];

    const titles: string[] = [];
    for (const { place, params } of extractMedalTemplates(text)) {
      const medal = MEDAL_PT[place] ?? place;
      const rawCombined = params.join(" ");
      const part1 = params[0] ? cleanWikiText(params[0]) : "";
      const part2 = params[1] ? cleanWikiText(params[1]) : "";
      const year = yearFromParts(part1, part2, rawCombined) ?? "?";

      let comp: string;
      let event: string;
      if (/olympic|jogos ol|summer youth/i.test(rawCombined)) {
        comp = "Olimpíadas";
        event = part2 || part1;
      } else if (part2) {
        comp = part1;
        event = part2;
      } else {
        comp = part1;
        event = "";
      }

      let line = `${year} ${medal} — ${translateHighlight(comp)}`;
      if (event) line += ` (${translateHighlight(event)})`;
      titles.push(line);
    }

    for (const line of text.split("\n")) {
      const stripped = line.trim();
      if (!stripped.startsWith("*")) continue;
      if (
        !/WTT|World Championship|Olympic|Grand Smash|Singapore Smash|Contender|Cup Finals|Asian Championship|World Cup|Olimp/i
          .test(stripped)
      ) continue;
      const clean = cleanWikiText(stripped.replace(/^\*\s*/, ""));
      if (/\b(19|20)\d{2}\b/.test(clean)) {
        titles.push(translateHighlight(clean));
      }
    }

    return titles;
  } catch {
    return [];
  }
}

function sortTitlesByYear(titles: string[]): string[] {
  const summary = titles.filter((t) =>
    t.includes("Títulos em") || t.includes("Títulos na carreira") ||
    t.includes("Singles titles:") || t.includes("Career titles:")
  );
  const rest = titles.filter((t) => !summary.includes(t));
  rest.sort((a, b) => {
    const ya = extractYear(a) ?? 0;
    const yb = extractYear(b) ?? 0;
    return yb - ya || a.localeCompare(b);
  });
  return [...summary, ...rest];
}

function mergeUnique(...lists: string[][]): string[] {
  const seen = new Set<string>();
  const out: string[] = [];
  for (const list of lists) {
    for (const item of list) {
      const t = translateHighlight(item.trim());
      if (!t || seen.has(t)) continue;
      seen.add(t);
      out.push(t);
    }
  }
  return out;
}

function recordChanged(
  existing: Record<string, unknown> | undefined,
  record: Record<string, unknown>,
): boolean {
  if (!existing) return true;
  const listEq = (a: unknown, b: unknown) => {
    const la = (a as string[] | null)?.map(String) ?? [];
    const lb = (b as string[] | null)?.map(String) ?? [];
    return la.length === lb.length && la.every((v, i) => v === lb[i]);
  };
  return existing.ranking !== record.ranking ||
    existing.ranking_points !== record.ranking_points ||
    existing.age !== record.age ||
    String(existing.height ?? "") !== String(record.height ?? "") ||
    String(existing.hand ?? "") !== String(record.hand ?? "") ||
    String(existing.ittf_id ?? "") !== String(record.ittf_id ?? "") ||
    String(existing.photo_url ?? "") !== String(record.photo_url ?? "") ||
    !listEq(existing.championships_won, record.championships_won);
}

async function wttGet(url: string): Promise<Response> {
  const sep = url.includes("?") ? "&" : "?";
  return fetch(`${url}${sep}q=${Date.now()}`, { headers: WTT_HEADERS });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  try {
    const { data: existingRows, error: fetchErr } = await supabase.from("athletes")
      .select(
        "name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url",
      );
    if (fetchErr) throw fetchErr;

    const existingByKey = new Map<string, Record<string, unknown>>();
    for (const row of existingRows ?? []) {
      existingByKey.set(
        athleteKey(String(row.name), String(row.gender)),
        row as Record<string, unknown>,
      );
    }

    const rankingResp = await wttGet(RANKING_URL);
    if (!rankingResp.ok) {
      throw new Error(`WTT ranking HTTP ${rankingResp.status}`);
    }
    const rankingPayload = await rankingResp.json();
    const allRankings = (rankingPayload.Result ?? []) as Record<string, unknown>[];
    const remoteMeta = allRankings[0] ?? {};

    const athletes: Record<string, unknown>[] = [];
    let changedCount = 0;

    for (const subEvent of ["MS", "WS"]) {
      const gender = subEvent === "MS" ? "male" : "female";
      const rows = allRankings
        .filter((r) => r.SubEventCode === subEvent)
        .sort(
          (a, b) =>
            (parseInt(a.CurrentRank) ?? 9999) - (parseInt(b.CurrentRank) ?? 9999),
        )
        .slice(0, 100);

      for (const row of rows) {
        const ittfId = String(row.IttfId ?? "");
        let profile: Record<string, unknown> = {};
        let card: Record<string, unknown> = {};

        if (ittfId) {
          const profileResp = await wttGet(`${PLAYERS_URL}?IttfId=${ittfId}`);
          if (profileResp.ok) {
            const payload = await profileResp.json();
            profile = (payload.Result?.[0] ?? {}) as Record<string, unknown>;
          }
          const cardResp = await wttGet(`${PLAYER_CARD_URL}${ittfId}`);
          if (cardResp.ok) {
            const payload = await cardResp.json();
            if (payload.details) {
              card = JSON.parse(payload.details);
            }
          }
        }

        const name = String(row.PlayerName ?? profile.PlayerName ?? "");
        const cardTitles = titlesFromCard(card);
        const wikiTitles = await titlesFromWiki(name);

        const photo = profile.HeadshotR ?? profile.HeadShot ?? profile.HeadshotL;
        const record: Record<string, unknown> = {
          name,
          gender,
          ittf_id: ittfId || null,
          ranking: parseInt(row.CurrentRank ?? row.RankingPosition),
          ranking_points: parseInt(
            row.RankingPointsYTD ?? row.RankingPointsCareer,
          ),
          age: parseInt(profile.Age ?? row.Age),
          height: parseFloat(card.Height ?? profile.Height),
          hand: profile.Handedness ?? card.Hand ?? null,
          championships_won: sortTitlesByYear(
            mergeUnique(cardTitles, wikiTitles),
          ),
          photo_url: photo
            ? String(photo)
              .replace(
                "https://wttsimfiles.blob.core.windows.net",
                "https://photofiles.worldtabletennis.com",
              )
              .replace(
                "https://wttnewtest.blob.core.windows.net",
                "https://photofiles.worldtabletennis.com",
              )
            : null,
          updated_at: new Date().toISOString(),
        };

        const key = athleteKey(name, gender);
        if (recordChanged(existingByKey.get(key), record)) {
          changedCount++;
        }
        athletes.push(record);
      }
    }

    const { error: upsertErr } = await supabase.from("athletes").upsert(
      athletes,
      { onConflict: "name,gender" },
    );
    if (upsertErr) throw upsertErr;

    return new Response(
      JSON.stringify({
        athletesSynced: athletes.length,
        athletesChanged: changedCount,
        rankingWeek: remoteMeta.RankingWeek ?? null,
        rankingYear: remoteMeta.RankingYear ?? null,
        hasUpdates: changedCount > 0 || (existingRows?.length ?? 0) === 0,
      }),
      {
        headers: {
          ...corsHeaders,
          "Content-Type": "application/json",
          "Connection": "keep-alive",
        },
      },
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return new Response(JSON.stringify({ error: message }), {
      status: 500,
      headers: {
        ...corsHeaders,
        "Content-Type": "application/json",
      },
    });
  }
});
