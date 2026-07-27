import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";
import { buildChampionships } from "./title_enrichment.ts";

const WTT_HEADERS = {
  Accept: "application/json, text/plain, */*",
  Referer: "https://www.worldtabletennis.com/",
  Origin: "https://www.worldtabletennis.com",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  ApiKey: "2bf8b222-532c-4c60-8ebe-eb6fdfebe84a",
};

const PLAYERS_URL =
  "https://wtt-ttu-connect-frontdoor-g6gwg6e2bgc6gdfm.a01.azurefd.net/Players/GetPlayers";
const PLAYER_CARD_URL =
  "https://wtt-website-api-prod-3-frontdoor-bddnb2haduafdze9.a01.azurefd.net/api/cms/PlayerCard/";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const SUMMARY_LINE =
  /^(Títulos em simples|Títulos em duplas|Títulos na carreira|Último resultado:)/i;

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

function parseIntSafe(value: unknown): number | null {
  if (value == null || value === "") return null;
  const n = Number.parseFloat(String(value));
  return Number.isFinite(n) ? Math.trunc(n) : null;
}

function parseFloatSafe(value: unknown): number | null {
  if (value == null || value === "") return null;
  const n = Number.parseFloat(String(value));
  return Number.isFinite(n) ? n : null;
}

function normalizePhotoUrl(url: unknown): string | null {
  if (url == null || url === "") return null;
  const text = String(url);
  if (text.toLowerCase().includes("dummy")) return null;
  return text
    .replace(
      "https://wttsimfiles.blob.core.windows.net",
      "https://photofiles.worldtabletennis.com",
    )
    .replace(
      "https://wttnewtest.blob.core.windows.net",
      "https://photofiles.worldtabletennis.com",
    );
}

function genderFromCode(code: unknown): "male" | "female" | null {
  const value = String(code ?? "").trim().toUpperCase();
  if (value === "M") return "male";
  if (value === "F") return "female";
  return null;
}

async function wttGet(url: string): Promise<Response> {
  const sep = url.includes("?") ? "&" : "?";
  return fetch(`${url}${sep}q=${Date.now()}`, { headers: WTT_HEADERS });
}

function preserveSummaryLines(existing?: Record<string, unknown> | null): string[] {
  const arr = (existing?.championships_won as string[] | null) ?? [];
  return arr.filter((line) => SUMMARY_LINE.test(String(line)));
}

type RegistryRow = {
  ittf_id: string;
  name: string;
  gender: string;
  country_code: string | null;
  ranking: number | null;
  ranking_points: number | null;
  photo_url: string | null;
};

async function handleSearch(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const query = String(body.query ?? "").trim();
  const genderFilter = body.gender === "male" || body.gender === "female"
    ? (body.gender as string)
    : null;

  if (query.length < 2) {
    return jsonResponse({ candidates: [] });
  }

  let registryQuery = supabase
    .from("player_registry")
    .select("*")
    .ilike("name", `%${query}%`)
    .limit(20);
  if (genderFilter) {
    registryQuery = registryQuery.eq("gender", genderFilter);
  }

  const { data: registryRows, error: registryErr } = await registryQuery;
  if (registryErr) throw registryErr;

  const candidatesByIttfId = new Map<string, RegistryRow>();
  for (const row of (registryRows ?? []) as RegistryRow[]) {
    candidatesByIttfId.set(row.ittf_id, row);
  }

  if (candidatesByIttfId.size < 8) {
    const resp = await wttGet(
      `${PLAYERS_URL}?PlayerName=${encodeURIComponent(query)}`,
    );
    if (resp.ok) {
      const payload = await resp.json();
      const results = (payload.Result ?? []) as Record<string, unknown>[];
      const toUpsert: RegistryRow[] = [];

      for (const row of results) {
        const ittfId = String(row.IttfId ?? "").trim();
        if (!ittfId) continue;
        const gender = genderFromCode(row.Gender);
        if (!gender) continue;
        if (genderFilter && gender !== genderFilter) continue;

        const existing = candidatesByIttfId.get(ittfId);
        const registryRow: RegistryRow = {
          ittf_id: ittfId,
          name: String(row.PlayerName ?? existing?.name ?? ""),
          gender,
          country_code: String(row.CountryCode ?? existing?.country_code ?? "") ||
            null,
          ranking: existing?.ranking ?? null,
          ranking_points: existing?.ranking_points ?? null,
          photo_url: normalizePhotoUrl(
            row.HeadshotR ?? row.HeadShot ?? row.HeadshotL,
          ) ?? existing?.photo_url ?? null,
        };

        candidatesByIttfId.set(ittfId, registryRow);
        toUpsert.push(registryRow);
      }

      if (toUpsert.length > 0) {
        const { error: upsertErr } = await supabase
          .from("player_registry")
          .upsert(
            toUpsert.map((r) => ({ ...r, updated_at: new Date().toISOString() })),
            { onConflict: "ittf_id" },
          );
        if (upsertErr) throw upsertErr;
      }
    }
  }

  const candidates = Array.from(candidatesByIttfId.values())
    .sort((a, b) => (a.ranking ?? 9999) - (b.ranking ?? 9999))
    .slice(0, 20);

  const ittfIds = candidates.map((c) => c.ittf_id);
  let hydratedIds = new Set<string>();
  if (ittfIds.length > 0) {
    const { data: existingAthletes } = await supabase
      .from("athletes")
      .select("ittf_id")
      .in("ittf_id", ittfIds);
    hydratedIds = new Set(
      (existingAthletes ?? []).map((r) => String((r as Record<string, unknown>).ittf_id)),
    );
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
      already_added: hydratedIds.has(c.ittf_id),
    })),
  });
}

async function handleHydrate(
  supabase: ReturnType<typeof createClient>,
  body: Record<string, unknown>,
): Promise<Response> {
  const ittfId = String(body.ittf_id ?? "").trim();
  if (!ittfId) {
    return jsonResponse({ error: "ittf_id é obrigatório" }, 400);
  }

  const { data: registryRow } = await supabase
    .from("player_registry")
    .select("*")
    .eq("ittf_id", ittfId)
    .maybeSingle();

  const { data: existingAthlete } = await supabase
    .from("athletes")
    .select(
      "id,name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url,country_code",
    )
    .eq("ittf_id", ittfId)
    .maybeSingle();

  const profileResp = await wttGet(`${PLAYERS_URL}?IttfId=${ittfId}`);
  let profile: Record<string, unknown> = {};
  if (profileResp.ok) {
    const payload = await profileResp.json();
    profile = (payload.Result?.[0] ?? {}) as Record<string, unknown>;
  }

  let card: Record<string, unknown> = {};
  const cardResp = await wttGet(`${PLAYER_CARD_URL}${ittfId}`);
  if (cardResp.ok) {
    const payload = await cardResp.json();
    if (payload.details) {
      try {
        card = JSON.parse(payload.details);
      } catch {
        card = {};
      }
    }
  }

  const name = String(
    profile.PlayerName ?? registryRow?.name ?? existingAthlete?.name ?? body.name ?? "",
  );
  if (!name) {
    return jsonResponse({ error: "Não foi possível identificar o atleta na WTT" }, 404);
  }

  const gender = genderFromCode(profile.Gender) ??
    (registryRow?.gender as string | undefined) ??
    (existingAthlete?.gender as string | undefined) ??
    (body.gender === "male" || body.gender === "female" ? body.gender as string : null);
  if (!gender) {
    return jsonResponse({ error: "Não foi possível determinar o gênero do atleta" }, 422);
  }

  const freshTitles = await buildChampionships(card, name);
  const eventLines = freshTitles.filter((line) => !SUMMARY_LINE.test(line));
  const championships_won = existingAthlete
    ? [...preserveSummaryLines(existingAthlete), ...eventLines]
    : freshTitles;

  const record = {
    name,
    gender,
    ittf_id: ittfId,
    // Registro tem apenas nomes/rankings do top1000; se não houver ranking
    // conhecido, o atleta fica com "sem ranking definido" em vez de inventar um.
    ranking: registryRow?.ranking ?? null,
    ranking_points: registryRow?.ranking_points ?? existingAthlete?.ranking_points ??
      parseIntSafe(profile.RankingPointsCareer) ?? null,
    age: parseIntSafe(profile.Age) ?? existingAthlete?.age ?? null,
    height: parseFloatSafe(card.Height ?? profile.Height) ?? existingAthlete?.height ?? null,
    hand: (profile.Handedness as string | undefined) ?? (card.Hand as string | undefined) ??
      existingAthlete?.hand ?? null,
    championships_won,
    photo_url: normalizePhotoUrl(profile.HeadshotR ?? profile.HeadShot ?? profile.HeadshotL) ??
      registryRow?.photo_url ?? existingAthlete?.photo_url ?? null,
    country_code: (profile.CountryCode as string | undefined) ?? registryRow?.country_code ??
      existingAthlete?.country_code ?? null,
    listed_in_home: true,
    profile_hydrated: true,
    updated_at: new Date().toISOString(),
  };

  const { data: upserted, error: upsertErr } = await supabase
    .from("athletes")
    .upsert(record, { onConflict: "name,gender" })
    .select("*")
    .single();
  if (upsertErr) throw upsertErr;

  return jsonResponse({ athlete: upserted });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL")!;
  const serviceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
  const supabase = createClient(supabaseUrl, serviceKey);

  try {
    let body: Record<string, unknown> = {};
    if (req.method === "POST") {
      try {
        body = (await req.json()) as Record<string, unknown>;
      } catch {
        body = {};
      }
    }

    const action = String(body.action ?? "");
    if (action === "search") {
      return await handleSearch(supabase, body);
    }
    if (action === "hydrate") {
      return await handleHydrate(supabase, body);
    }

    return jsonResponse({ error: `Ação desconhecida: ${action}` }, 400);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
