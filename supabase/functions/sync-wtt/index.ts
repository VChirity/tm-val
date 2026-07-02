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

const RANKING_URL =
  "https://wtt-web-frontdoor-withoutcache-cqakg0andqf5hchn.a01.azurefd.net/ranking/SEN_SINGLES.json";
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

const TOTAL_ATHLETES = 200;
const ATHLETES_PER_GENDER = 100;

type RankingTarget = {
  row: Record<string, unknown>;
  gender: string;
};

function collectAllTargets(
  allRankings: Record<string, unknown>[],
): RankingTarget[] {
  const targets: RankingTarget[] = [];

  for (const subEvent of ["MS", "WS"]) {
    const gender = subEvent === "MS" ? "male" : "female";
    const rows = allRankings
      .filter((r) => r.SubEventCode === subEvent)
      .sort(
        (a, b) =>
          (parseInt(a.CurrentRank) ?? 9999) - (parseInt(b.CurrentRank) ?? 9999),
      )
      .slice(0, ATHLETES_PER_GENDER);

    for (const row of rows) {
      targets.push({ row, gender });
    }
  }

  return targets;
}

async function buildAthleteRecord(
  row: Record<string, unknown>,
  gender: string,
): Promise<Record<string, unknown>> {
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
  const photo = profile.HeadshotR ?? profile.HeadShot ?? profile.HeadshotL;
  return {
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
    championships_won: await buildChampionships(card, name),
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
}

function parseBatchParams(req: Request, body: Record<string, unknown>) {
  const url = new URL(req.url);
  const offsetRaw = body.offset ?? url.searchParams.get("offset");
  const limitRaw = body.limit ?? url.searchParams.get("limit");

  const offset = Math.max(0, parseInt(offsetRaw) ?? 0);
  const limit = Math.min(
    TOTAL_ATHLETES,
    Math.max(1, parseInt(limitRaw) ?? TOTAL_ATHLETES),
  );

  return { offset, limit };
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

    const { offset, limit } = parseBatchParams(req, body);
    const batchEnd = Math.min(offset + limit, TOTAL_ATHLETES);

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
    const allTargets = collectAllTargets(allRankings);
    const batchTargets = allTargets.slice(offset, batchEnd);

    const athletes: Record<string, unknown>[] = [];
    let changedCount = 0;
    let lastAthleteName: string | null = null;

    for (const target of batchTargets) {
      const record = await buildAthleteRecord(target.row, target.gender);
      lastAthleteName = String(record.name ?? "");

      const key = athleteKey(
        String(record.name ?? ""),
        String(record.gender ?? ""),
      );
      if (recordChanged(existingByKey.get(key), record)) {
        changedCount++;
      }
      athletes.push(record);
    }

    if (athletes.length > 0) {
      const { error: upsertErr } = await supabase.from("athletes").upsert(
        athletes,
        { onConflict: "name,gender" },
      );
      if (upsertErr) throw upsertErr;
    }

    const processed = offset + athletes.length;
    const total = allTargets.length || TOTAL_ATHLETES;
    const done = processed >= total;

    return new Response(
      JSON.stringify({
        athletesSynced: athletes.length,
        athletesChanged: changedCount,
        processed,
        total,
        offset,
        done,
        currentAthlete: lastAthleteName,
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
