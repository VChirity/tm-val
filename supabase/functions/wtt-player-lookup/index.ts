import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const WTT_HEADERS = {
  Accept: "application/json, text/plain, */*",
  Referer: "https://www.worldtabletennis.com/",
  Origin: "https://www.worldtabletennis.com",
  "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  ApiKey: "2bf8b222-532c-4c60-8ebe-eb6fdfebe84a",
};
const PLAYERS_URL =
  "https://wtt-ttu-connect-frontdoor-g6gwg6e2bgc6gdfm.a01.azurefd.net/Players/GetPlayers";
const PLAYER_CARD_URL =
  "https://wtt-website-api-prod-3-frontdoor-bddnb2haduafdze9.a01.azurefd.net/api/cms/PlayerCard/";
const WIKI_HEADERS = { "User-Agent": "TM-Val/1.0 (tm-val-app)" };
const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

type WikiLang = "en" | "pt";
type RegistryRow = {
  ittf_id: string;
  name: string;
  gender: string;
  country_code: string | null;
  ranking: number | null;
  ranking_points: number | null;
  photo_url: string | null;
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
function parseIntSafe(v: unknown): number | null {
  if (v == null || v === "") return null;
  const n = Number.parseFloat(String(v));
  return Number.isFinite(n) ? Math.trunc(n) : null;
}
function parseFloatSafe(v: unknown): number | null {
  if (v == null || v === "") return null;
  const n = Number.parseFloat(String(v));
  return Number.isFinite(n) ? n : null;
}
function normalizePhotoUrl(url: unknown): string | null {
  if (url == null || url === "") return null;
  const text = String(url);
  if (text.toLowerCase().includes("dummy")) return null;
  return text
    .replace("https://wttsimfiles.blob.core.windows.net", "https://photofiles.worldtabletennis.com")
    .replace("https://wttnewtest.blob.core.windows.net", "https://photofiles.worldtabletennis.com");
}
function genderFromCode(code: unknown): "male" | "female" | null {
  const v = String(code ?? "").trim().toUpperCase();
  if (v === "M") return "male";
  if (v === "F") return "female";
  return null;
}
function stripDiacritics(text: string): string {
  return text.normalize("NFD").replace(/\p{M}/gu, "");
}
function escapeIlike(text: string): string {
  return text.replace(/[%_,]/g, " ");
}
function normName(text: string): string {
  return stripDiacritics(text).toLowerCase().replace(/[^a-z0-9\s]/g, " ").replace(/\s+/g, " ").trim();
}
function isBrazilian(code?: string | null): boolean {
  const c = String(code ?? "").toUpperCase();
  return c === "BRA" || c === "BR";
}
async function wttGet(url: string): Promise<Response> {
  const sep = url.includes("?") ? "&" : "?";
  return fetch(`${url}${sep}q=${Date.now()}`, { headers: WTT_HEADERS });
}

/** Only trust WTT/storage headshots — never keep random Wikimedia. */
function isTrustedPhoto(url: string | null | undefined): boolean {
  if (!url) return false;
  const t = String(url);
  if (t.toLowerCase().includes("dummy")) return false;
  if (t.includes("upload.wikimedia.org") || t.includes("wikipedia")) return false;
  return (
    t.includes("worldtabletennis.com") ||
    t.includes("wttsimfiles") ||
    t.includes("photofiles.worldtabletennis") ||
    t.includes("supabase.co/storage")
  );
}
function pickPhoto(...cands: Array<unknown>): string | null {
  for (const c of cands) {
    const n = normalizePhotoUrl(c);
    if (n && isTrustedPhoto(n)) return n;
  }
  return null;
}

const MANUAL_PROFILE_FIELDS = [
  "age",
  "height",
  "hand",
  "ranking_points",
  "short_bio",
  "photo_url",
] as const;

function isManualField(
  existing: Record<string, unknown> | null | undefined,
  field: string,
): boolean {
  const mf = existing?.manual_fields;
  if (mf == null || typeof mf !== "object" || Array.isArray(mf)) return false;
  return (mf as Record<string, unknown>)[field] === true;
}

function preserveManualFields(
  record: Record<string, unknown>,
  existing?: Record<string, unknown> | null,
): Record<string, unknown> {
  if (!existing) return record;
  const out = { ...record };
  for (const field of MANUAL_PROFILE_FIELDS) {
    if (isManualField(existing, field)) {
      out[field] = existing[field] ?? null;
    }
  }
  if (existing.manual_fields != null) {
    out.manual_fields = existing.manual_fields;
  }
  return out;
}

const BAD_IMG =
  /\b(ensaio|ensaios|banner|logo|poster|cover|capa|crowd|festival|concert|show|parade|desfile|mapa|flag|bandeira)\b/i;

function titleMatchesPerson(pageTitle: string, playerName: string): boolean {
  if (!pageTitle || /\((desambiguação|disambiguation)\)/i.test(pageTitle)) return false;
  const titleNorm = normName(pageTitle.replace(/\(.*?\)/g, " "));
  const parts = normName(playerName).split(" ").filter(Boolean);
  const given = parts[0] ?? "";
  const family = parts[parts.length - 1] ?? "";
  if (!given || !family) return false;
  return titleNorm.includes(given) && titleNorm.includes(family);
}

async function wikiPageTitle(name: string, lang: WikiLang): Promise<string | null> {
  const queries = lang === "pt"
    ? [`"${name}"`, `${name} tênis de mesa`, `${name} mesa-tenista`, name]
    : [`"${name}"`, `${name} table tennis`, name];
  for (const query of queries) {
    const u = new URL(`https://${lang}.wikipedia.org/w/api.php`);
    u.searchParams.set("action", "query");
    u.searchParams.set("list", "search");
    u.searchParams.set("srsearch", query);
    u.searchParams.set("srlimit", "8");
    u.searchParams.set("format", "json");
    const resp = await fetch(u, { headers: WIKI_HEADERS });
    if (!resp.ok) continue;
    const hits = (await resp.json())?.query?.search ?? [];
    for (const hit of hits) {
      const title = String(hit.title ?? "");
      if (!titleMatchesPerson(title, name)) continue;
      // reject disambiguation via pageprops
      const p = new URL(`https://${lang}.wikipedia.org/w/api.php`);
      p.searchParams.set("action", "query");
      p.searchParams.set("titles", title);
      p.searchParams.set("prop", "pageprops");
      p.searchParams.set("format", "json");
      p.searchParams.set("redirects", "1");
      const pr = await fetch(p, { headers: WIKI_HEADERS });
      if (pr.ok) {
        const pages = (await pr.json())?.query?.pages ?? {};
        let disambig = false;
        for (const page of Object.values(pages) as Record<string, unknown>[]) {
          if ((page.pageprops as Record<string, unknown> | undefined)?.disambiguation != null) {
            disambig = true;
          }
        }
        if (disambig) continue;
      }
      return title;
    }
  }
  return null;
}

async function fetchWikipediaPhoto(name: string, countryCode?: string | null): Promise<string | null> {
  const langs: WikiLang[] = isBrazilian(countryCode) ? ["pt", "en"] : ["en", "pt"];
  for (const lang of langs) {
    try {
      const page = await wikiPageTitle(name, lang);
      if (!page) continue;
      const u = new URL(`https://${lang}.wikipedia.org/w/api.php`);
      u.searchParams.set("action", "query");
      u.searchParams.set("titles", page);
      u.searchParams.set("prop", "pageimages");
      u.searchParams.set("pithumbsize", "640");
      u.searchParams.set("piprop", "thumbnail|original|name");
      u.searchParams.set("format", "json");
      u.searchParams.set("redirects", "1");
      const resp = await fetch(u, { headers: WIKI_HEADERS });
      if (!resp.ok) continue;
      const pages = (await resp.json())?.query?.pages ?? {};
      for (const p of Object.values(pages) as Record<string, unknown>[]) {
        const thumb = p.thumbnail as { source?: string; width?: number; height?: number } | undefined;
        const original = p.original as { source?: string; width?: number; height?: number } | undefined;
        const src = thumb?.source ?? original?.source;
        const w = thumb?.width ?? original?.width ?? 0;
        const h = thumb?.height ?? original?.height ?? 0;
        const fname = String(p.pageimage ?? src ?? "");
        if (!src || String(src).toLowerCase().includes("placeholder")) continue;
        if (BAD_IMG.test(fname) || BAD_IMG.test(src)) continue;
        if (w > 0 && h > 0 && (w / h > 1.35 || w < 80 || h < 80)) continue;
        return String(src);
      }
    } catch { /* next */ }
  }
  return null;
}

function truncateBio(text: string, maxLen = 280): string {
  const cleaned = text.replace(/\s+/g, " ").trim();
  if (cleaned.length <= maxLen) return cleaned;
  const slice = cleaned.slice(0, maxLen);
  const lastSpace = slice.lastIndexOf(" ");
  return `${(lastSpace > 120 ? slice.slice(0, lastSpace) : slice).replace(/[.,;:\s]+$/g, "")}…`;
}

function sanitizeBio(extract: string, playerName: string): string | null {
  const text = extract.replace(/\s+/g, " ").trim();
  if (!text) return null;
  const norm = stripDiacritics(text).toLowerCase();
  const parts = normName(playerName).split(" ").filter(Boolean);
  const given = parts[0] ?? "";
  const family = parts[parts.length - 1] ?? "";
  if (given && !norm.includes(given) && family && !norm.includes(family)) return null;
  const mentionsReturn =
    /\b(retorn|voltou a|volta a|ativa|ativo|atualmente|hoje|comentarista|narradora|narrador)\b/i.test(text);
  const onlyEx = /\bé uma?\s+ex-|\bis a\s+former\b|\bretired\b/i.test(text);
  let out = text;
  if (onlyEx && mentionsReturn) {
    out = text
      .replace(/\bé uma?\s+ex-jogadora\b/gi, "é jogadora")
      .replace(/\bé um\s+ex-jogador\b/gi, "é jogador")
      .replace(/\bis a\s+former\b/gi, "is a")
      .replace(/\bretired\s+/gi, "");
  }
  const partsSent = out.match(/[^.!?]+[.!?]+|[^.!?]+$/g) ?? [out];
  return truncateBio(partsSent.slice(0, 2).join(" ").trim());
}

async function fetchWikipediaBio(name: string, countryCode?: string | null): Promise<string | null> {
  const langs: WikiLang[] = isBrazilian(countryCode) ? ["pt", "en"] : ["en", "pt"];
  for (const lang of langs) {
    try {
      const page = await wikiPageTitle(name, lang);
      if (!page) continue;
      const u = new URL(`https://${lang}.wikipedia.org/w/api.php`);
      u.searchParams.set("action", "query");
      u.searchParams.set("titles", page);
      u.searchParams.set("prop", "extracts");
      u.searchParams.set("exintro", "1");
      u.searchParams.set("explaintext", "1");
      u.searchParams.set("format", "json");
      u.searchParams.set("redirects", "1");
      const resp = await fetch(u, { headers: WIKI_HEADERS });
      if (!resp.ok) continue;
      const pages = (await resp.json())?.query?.pages ?? {};
      for (const p of Object.values(pages) as Record<string, unknown>[]) {
        const extract = String(p.extract ?? "").trim();
        if (!extract) continue;
        const bio = sanitizeBio(extract, name);
        if (bio) return bio;
      }
    } catch { /* next */ }
  }
  return null;
}

function knownShortBio(name: string): string | null {
  const n = normName(name);
  if (n.includes("valesca") && n.includes("maranhao")) {
    return "Valesca Maranhão é mesa-tenista e comentarista brasileira. Atleta ativa, também atua na transmissão esportiva.";
  }
  return null;
}

function bioAboutPlayer(bio: string | null | undefined, name: string): boolean {
  if (!bio) return false;
  const parts = normName(name).split(" ").filter(Boolean);
  const given = parts[0] ?? "";
  const family = parts[parts.length - 1] ?? "";
  const norm = stripDiacritics(bio).toLowerCase();
  if (given && norm.includes(given)) return true;
  if (family && family.length >= 4 && norm.includes(family)) return true;
  return false;
}

function mergeTitles(...sources: string[][]): string[] {
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
function sortTitlesByYear(titles: string[]): string[] {
  const yearRe = /\b((?:19|20)\d{2})\b/;
  return [...titles].sort((a, b) => {
    const ya = Number.parseInt(a.match(yearRe)?.[1] ?? "0", 10);
    const yb = Number.parseInt(b.match(yearRe)?.[1] ?? "0", 10);
    return yb - ya || a.localeCompare(b);
  });
}
async function buildChampionships(card: Record<string, unknown>): Promise<string[]> {
  const titles: string[] = [];
  if (card.singles_titles) titles.push(`Títulos em simples: ${card.singles_titles}`);
  if (card.doubles_titles) titles.push(`Títulos em duplas: ${card.doubles_titles}`);
  try {
    const statsRaw = card.stats;
    const stats = typeof statsRaw === "string" ? JSON.parse(statsRaw) : statsRaw;
    const career = stats?.career_titles ?? stats?.tournament_wins;
    if (career) titles.push(`Títulos na carreira: ${career}`);
  } catch { /* ignore */ }
  return sortTitlesByYear(titles);
}

async function handleSearch(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const queryRaw = String(body.query ?? "").trim();
  const queryPlain = stripDiacritics(queryRaw);
  const genderFilter = body.gender === "male" || body.gender === "female"
    ? (body.gender as string) : null;
  if (queryRaw.length < 2) return jsonResponse({ candidates: [] });

  const q1 = escapeIlike(queryRaw);
  const q2 = escapeIlike(queryPlain);
  let registryQuery = supabase.from("player_registry").select("*").limit(20);
  registryQuery = q1.toLowerCase() !== q2.toLowerCase()
    ? registryQuery.or(`name.ilike.%${q1}%,name.ilike.%${q2}%`)
    : registryQuery.ilike("name", `%${q1}%`);
  if (genderFilter) registryQuery = registryQuery.eq("gender", genderFilter);

  const { data: registryRows, error: registryErr } = await registryQuery;
  if (registryErr) throw registryErr;

  const byId = new Map<string, RegistryRow>();
  for (const row of (registryRows ?? []) as RegistryRow[]) {
    byId.set(row.ittf_id, { ...row, photo_url: pickPhoto(row.photo_url) });
  }

  if (byId.size < 8) {
    const resp = await wttGet(
      `${PLAYERS_URL}?PlayerName=${encodeURIComponent(queryPlain || queryRaw)}`,
    );
    if (resp.ok) {
      const results = ((await resp.json()).Result ?? []) as Record<string, unknown>[];
      const toUpsert: RegistryRow[] = [];
      for (const row of results) {
        const ittfId = String(row.IttfId ?? "").trim();
        if (!ittfId) continue;
        const gender = genderFromCode(row.Gender);
        if (!gender || (genderFilter && gender !== genderFilter)) continue;
        const existing = byId.get(ittfId);
        const registryRow: RegistryRow = {
          ittf_id: ittfId,
          name: String(row.PlayerName ?? existing?.name ?? ""),
          gender,
          country_code: String(row.CountryCode ?? existing?.country_code ?? "") || null,
          ranking: existing?.ranking ?? null,
          ranking_points: existing?.ranking_points ?? null,
          photo_url: pickPhoto(row.HeadshotR, row.HeadShot, row.HeadshotL, existing?.photo_url),
        };
        byId.set(ittfId, registryRow);
        toUpsert.push(registryRow);
      }
      if (toUpsert.length > 0) {
        const { error } = await supabase.from("player_registry").upsert(
          toUpsert.map((r) => ({ ...r, updated_at: new Date().toISOString() })),
          { onConflict: "ittf_id" },
        );
        if (error) throw error;
      }
    }
  }

  const candidates = Array.from(byId.values())
    .sort((a, b) => (a.ranking ?? 9999) - (b.ranking ?? 9999))
    .slice(0, 20);

  // Strict wiki portrait only when missing WTT photo; low-confidence → leave null.
  const missing = candidates.filter((c) => !c.photo_url).slice(0, 5);
  await Promise.all(missing.map(async (c) => {
    const photo = await Promise.race([
      fetchWikipediaPhoto(c.name, c.country_code),
      new Promise<null>((r) => setTimeout(() => r(null), 2500)),
    ]);
    if (photo) c.photo_url = photo;
  }));

  const ittfIds = candidates.map((c) => c.ittf_id);
  let hydrated = new Set<string>();
  if (ittfIds.length > 0) {
    const { data } = await supabase.from("athletes").select("ittf_id").in("ittf_id", ittfIds);
    hydrated = new Set((data ?? []).map((r) => String((r as Record<string, unknown>).ittf_id)));
  }

  return jsonResponse({
    candidates: candidates.map((c) => ({
      ittf_id: c.ittf_id,
      name: c.name,
      gender: c.gender,
      country_code: c.country_code,
      ranking: c.ranking,
      ranking_points: c.ranking_points,
      photo_url: c.photo_url,
      already_added: hydrated.has(c.ittf_id),
    })),
  });
}

async function handleHydrate(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const ittfId = String(body.ittf_id ?? "").trim();
  if (!ittfId) return jsonResponse({ error: "ittf_id é obrigatório" }, 400);

  const { data: registryRow } = await supabase.from("player_registry").select("*").eq("ittf_id", ittfId).maybeSingle();
  const { data: existingAthlete } = await supabase.from("athletes").select(
    "id,name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url,country_code,short_bio,manual_fields",
  ).eq("ittf_id", ittfId).maybeSingle();

  const profileResp = await wttGet(`${PLAYERS_URL}?IttfId=${ittfId}`);
  let profile: Record<string, unknown> = {};
  if (profileResp.ok) profile = ((await profileResp.json()).Result?.[0] ?? {}) as Record<string, unknown>;

  let card: Record<string, unknown> = {};
  const cardResp = await wttGet(`${PLAYER_CARD_URL}${ittfId}`);
  if (cardResp.ok) {
    const payload = await cardResp.json();
    if (payload.details) {
      try { card = JSON.parse(payload.details); } catch { card = {}; }
    }
  }

  const name = String(profile.PlayerName ?? registryRow?.name ?? existingAthlete?.name ?? body.name ?? "");
  if (!name) return jsonResponse({ error: "Não foi possível identificar o atleta na WTT" }, 404);
  const gender = genderFromCode(profile.Gender) ??
    (registryRow?.gender as string | undefined) ??
    (existingAthlete?.gender as string | undefined) ??
    (body.gender === "male" || body.gender === "female" ? body.gender as string : null);
  if (!gender) return jsonResponse({ error: "Não foi possível determinar o gênero do atleta" }, 422);

  const country_code = (profile.CountryCode as string | undefined) ??
    registryRow?.country_code ?? existingAthlete?.country_code ?? null;

  const freshTitles = await buildChampionships(card);
  const existingLines = ((existingAthlete?.championships_won as string[] | null) ?? []).map(String);
  const championships_won = existingAthlete
    ? sortTitlesByYear(mergeTitles(existingLines, freshTitles))
    : freshTitles;

  let photo_url = pickPhoto(
    profile.HeadshotR, profile.HeadShot, profile.HeadshotL,
    registryRow?.photo_url, existingAthlete?.photo_url,
  );
  if (!photo_url) photo_url = await fetchWikipediaPhoto(name, country_code);

  let short_bio = bioAboutPlayer(existingAthlete?.short_bio as string | undefined, name)
    ? (existingAthlete?.short_bio as string) : null;
  if (!short_bio) {
    short_bio = (await fetchWikipediaBio(name, country_code)) ?? knownShortBio(name);
  }
  if (!short_bio) short_bio = knownShortBio(name);

  const record = preserveManualFields({
    name,
    gender,
    ittf_id: ittfId,
    ranking: registryRow?.ranking ?? null,
    ranking_points: registryRow?.ranking_points ?? existingAthlete?.ranking_points ??
      parseIntSafe(profile.RankingPointsCareer) ?? null,
    age: parseIntSafe(profile.Age) ?? existingAthlete?.age ?? null,
    height: parseFloatSafe(card.Height ?? profile.Height) ?? existingAthlete?.height ?? null,
    hand: (profile.Handedness as string | undefined) ?? (card.Hand as string | undefined) ??
      existingAthlete?.hand ?? null,
    championships_won,
    photo_url,
    short_bio,
    country_code,
    listed_in_home: true,
    profile_hydrated: true,
    updated_at: new Date().toISOString(),
  }, existingAthlete as Record<string, unknown> | null);

  await supabase.from("player_registry").upsert({
    ittf_id: ittfId,
    name,
    gender,
    country_code,
    ranking: registryRow?.ranking ?? null,
    ranking_points: registryRow?.ranking_points ?? null,
    photo_url,
    updated_at: new Date().toISOString(),
  }, { onConflict: "ittf_id" });

  const { data: upserted, error: upsertErr } = await supabase
    .from("athletes")
    .upsert(record, { onConflict: "name,gender" })
    .select("*")
    .single();
  if (upsertErr) throw upsertErr;
  return jsonResponse({ athlete: upserted });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: corsHeaders });
  const supabase = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  try {
    let body: Record<string, unknown> = {};
    if (req.method === "POST") {
      try { body = (await req.json()) as Record<string, unknown>; } catch { body = {}; }
    }
    const action = String(body.action ?? "");
    if (action === "search") return await handleSearch(supabase, body);
    if (action === "hydrate") return await handleHydrate(supabase, body);
    return jsonResponse({ error: `Ação desconhecida: ${action}` }, 400);
  } catch (error) {
    return jsonResponse({ error: error instanceof Error ? error.message : String(error) }, 500);
  }
});
