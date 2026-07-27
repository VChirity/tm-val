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

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

const TOTAL_ATHLETES = 200;
const ATHLETES_PER_GENDER = 100;

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

function photoFromRankingRow(row: Record<string, unknown>): string | null {
  const candidate = row.HeadshotR ??
    row.HeadShot ??
    row.HeadshotL ??
    row.PlayerPhoto ??
    row.PhotoUrl ??
    row.HeadshotUrl;
  return normalizePhotoUrl(candidate);
}

/** Campos da ficha que o usuário pode travar via athletes.manual_fields. */
const MANUAL_PROFILE_FIELDS = [
  "age",
  "height",
  "hand",
  "ranking_points",
  "short_bio",
  "photo_url",
] as const;

function isManualField(
  existing: Record<string, unknown> | undefined,
  field: string,
): boolean {
  const mf = existing?.manual_fields;
  if (mf == null || typeof mf !== "object" || Array.isArray(mf)) return false;
  return (mf as Record<string, unknown>)[field] === true;
}

/** Mantém valores manuais e o mapa manual_fields no payload de upsert. */
function preserveManualFields(
  record: Record<string, unknown>,
  existing?: Record<string, unknown>,
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

function recordChangedFast(
  existing: Record<string, unknown> | undefined,
  record: Record<string, unknown>,
): boolean {
  if (!existing) return true;
  return existing.ranking !== record.ranking ||
    existing.ranking_points !== record.ranking_points ||
    String(existing.ittf_id ?? "") !== String(record.ittf_id ?? "") ||
    String(existing.photo_url ?? "") !== String(record.photo_url ?? "");
}

function recordChangedFull(
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

function buildAthleteRecordFast(
  row: Record<string, unknown>,
  gender: string,
  existing?: Record<string, unknown>,
): Record<string, unknown> {
  const name = String(row.PlayerName ?? "");
  const ittfId = String(row.IttfId ?? "");
  const rankingPhoto = photoFromRankingRow(row);
  const existingPhoto = existing?.photo_url != null
    ? String(existing.photo_url)
    : null;

  return {
    name,
    gender,
    ittf_id: ittfId || null,
    ranking: parseInt(row.CurrentRank ?? row.RankingPosition),
    ranking_points: parseInt(
      row.RankingPointsYTD ?? row.RankingPointsCareer,
    ),
    age: parseInt(row.Age) ?? existing?.age ?? null,
    height: existing?.height ?? null,
    hand: existing?.hand ?? null,
    championships_won: existing?.championships_won ?? [],
    photo_url: rankingPhoto ?? existingPhoto,
    listed_in_home: true,
    profile_hydrated: existing?.profile_hydrated ?? true,
    updated_at: new Date().toISOString(),
  };
}

async function buildAthleteRecordFull(
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
  const photo = profile.HeadshotR ?? profile.HeadShot ?? profile.HeadshotL ??
    photoFromRankingRow(row);
  const { buildChampionships } = await importEnrichment();
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
    photo_url: normalizePhotoUrl(photo),
    listed_in_home: true,
    profile_hydrated: true,
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

function isFullMode(body: Record<string, unknown>): boolean {
  return body.full === true || body.mode === "full";
}

function isTitlesMode(body: Record<string, unknown>): boolean {
  return body.titles === true || body.mode === "titles";
}

const SUMMARY_LINE =
  /^(Títulos em simples|Títulos em duplas|Títulos na carreira|Último resultado:)/i;

function preserveSummaryLines(existing?: Record<string, unknown>): string[] {
  const arr = (existing?.championships_won as string[] | null) ?? [];
  return arr.filter((line) => SUMMARY_LINE.test(String(line)));
}

function championshipsEqual(a: unknown, b: unknown): boolean {
  const la = (a as string[] | null)?.map(String) ?? [];
  const lb = (b as string[] | null)?.map(String) ?? [];
  return la.length === lb.length && la.every((v, i) => v === lb[i]);
}

async function importEnrichment() {
  try {
    return await import("./title_enrichment.ts");
  } catch {
    return await import(
      "https://raw.githubusercontent.com/VChirity/tm-val/main/supabase/functions/sync-wtt/title_enrichment.ts",
    );
  }
}

function titlePriority(title: string): number {
  const lower = title.toLowerCase();
  if (lower.includes("campeão") || lower.includes("campeã")) return 4;
  if (lower.includes("2° lugar") || lower.includes("prata")) return 3;
  if (lower.includes("3° lugar") || lower.includes("bronze")) return 2;
  if (lower.includes("4° lugar") || lower.includes("5-8")) return 1;
  return 0;
}

function titleIdentityKey(title: string): string {
  const year = (title.match(/\b((?:19|20)\d{2})\b/) ?? [])[1] ?? "";
  const lower = title.toLowerCase();
  let category = "simples";
  if (lower.includes("duplas mistas") || lower.includes("— mista")) {
    category = "mista";
  } else if (lower.includes("duplas")) category = "duplas";
  else if (lower.includes("equipe")) category = "equipe";
  const rawEvent = title.includes(":")
    ? title.split(":", 1)[0].trim().toLowerCase()
    : lower;
  let event = rawEvent;
  if (event.startsWith("nacional")) event = "nacional";
  else if (event.includes("campeonato mundial")) event = "campeonato mundial";
  else if (event.includes("pan-americano")) event = "pan-americano";
  else if (event.includes("copa do mundo")) event = "copa do mundo";
  else if (event.includes("grand smash")) event = "wtt grand smash";
  else if (event.includes("wtt finals") || event.includes("cup finals")) {
    event = "wtt finals";
  } else if (event.includes("star contender")) event = "wtt star contender";
  else if (event.includes("wtt contender")) event = "wtt contender";
  else if (event.includes("wtt champions")) event = "wtt champions";
  const paren = title.match(/\(([^)]+)\)/);
  let location = "";
  if (paren) {
    location = paren[1]
      .toLowerCase()
      .replace(/\b(?:19|20)\d{2}\b/g, "")
      .split("—")[0]
      .trim()
      .replace(/\s+/g, " ");
  }
  return `${event}|${year}|${location}|${category}`;
}

/** Merge local (não depende de exports do title_enrichment). */
function mergeTitleLists(...sources: string[][]): string[] {
  const best = new Map<string, [number, string]>();
  const order: string[] = [];
  for (const source of sources) {
    for (const raw of source) {
      const text = String(raw).trim();
      if (!text) continue;
      const key = titleIdentityKey(text);
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
  const seen = new Set<string>();
  const merged: string[] = [];
  for (const key of order) {
    const entry = best.get(key);
    if (!entry) continue;
    if (seen.has(entry[1])) continue;
    seen.add(entry[1]);
    merged.push(entry[1]);
  }
  return merged;
}

function sortTitleLists(titles: string[]): string[] {
  const summary = titles.filter((t) => SUMMARY_LINE.test(t));
  const rest = titles.filter((t) => !SUMMARY_LINE.test(t));
  rest.sort((a, b) => {
    const ya = Number.parseInt(a.match(/\b((?:19|20)\d{2})\b/)?.[1] ?? "0", 10);
    const yb = Number.parseInt(b.match(/\b((?:19|20)\d{2})\b/)?.[1] ?? "0", 10);
    return yb - ya || a.localeCompare(b);
  });
  return [...summary, ...rest];
}

function eventTitleLines(titles: unknown): string[] {
  const arr = (titles as string[] | null)?.map(String) ?? [];
  return arr.filter((line) => !SUMMARY_LINE.test(line));
}

function countEventTitles(titles: unknown): number {
  return eventTitleLines(titles).length;
}

async function buildAthleteRecordTitles(
  row: Record<string, unknown>,
  gender: string,
  existing?: Record<string, unknown>,
): Promise<Record<string, unknown>> {
  const name = String(row.PlayerName ?? existing?.name ?? "");
  const existingTitles =
    (existing?.championships_won as string[] | null)?.map(String) ?? [];
  const { buildChampionships } = await importEnrichment();
  const fresh = await buildChampionships({}, name);
  const freshEvents = eventTitleLines(fresh);
  const existingEvents = eventTitleLines(existingTitles);

  // Nunca substituir por conjunto mais pobre / vazio.
  let championships_won: string[];
  if (freshEvents.length === 0) {
    championships_won = existingTitles;
  } else {
    const freshSummary = fresh.filter((line) => SUMMARY_LINE.test(line));
    const summary = freshSummary.length > 0
      ? freshSummary
      : preserveSummaryLines(existing);
    const mergedEvents = mergeTitleLists(existingEvents, freshEvents);
    championships_won = sortTitleLists([...summary, ...mergedEvents]);
    if (countEventTitles(championships_won) < existingEvents.length) {
      championships_won = existingTitles;
    }
  }

  return {
    name,
    gender,
    ittf_id: existing?.ittf_id ?? (String(row.IttfId ?? "") || null),
    ranking: parseInt(row.CurrentRank ?? row.RankingPosition) ??
      existing?.ranking ?? null,
    ranking_points: parseInt(
      row.RankingPointsYTD ?? row.RankingPointsCareer,
    ) ?? existing?.ranking_points ?? null,
    age: existing?.age ?? parseInt(row.Age),
    height: existing?.height ?? null,
    hand: existing?.hand ?? null,
    championships_won,
    photo_url: existing?.photo_url ?? photoFromRankingRow(row),
    listed_in_home: true,
    profile_hydrated: true,
    updated_at: new Date().toISOString(),
  };
}

function titlesChanged(
  existing: Record<string, unknown> | undefined,
  record: Record<string, unknown>,
): boolean {
  if (!existing) return true;
  return !championshipsEqual(existing.championships_won, record.championships_won);
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

    const fullMode = isFullMode(body);
    const titlesMode = isTitlesMode(body);

    const { data: existingRows, error: fetchErr } = await supabase.from("athletes")
      .select(
        "name,gender,ranking,ranking_points,age,height,hand,championships_won,ittf_id,photo_url,profile_hydrated,short_bio,manual_fields",
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

    if (!fullMode && !titlesMode) {
      const athletesToUpsert: Record<string, unknown>[] = [];
      let changedCount = 0;

      for (const target of allTargets) {
        const name = String(target.row.PlayerName ?? "");
        const key = athleteKey(name, target.gender);
        const existing = existingByKey.get(key);
        const record = preserveManualFields(
          buildAthleteRecordFast(
            target.row,
            target.gender,
            existing,
          ),
          existing,
        );

        if (recordChangedFast(existing, record)) {
          changedCount++;
          athletesToUpsert.push(record);
        }
      }

      if (athletesToUpsert.length > 0) {
        const { error: upsertErr } = await supabase.from("athletes").upsert(
          athletesToUpsert,
          { onConflict: "name,gender" },
        );
        if (upsertErr) throw upsertErr;
      }

      const total = allTargets.length || TOTAL_ATHLETES;

      return new Response(
        JSON.stringify({
          mode: "fast",
          athletesSynced: athletesToUpsert.length,
          athletesChanged: changedCount,
          processed: total,
          total,
          done: true,
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
    }

    if (titlesMode) {
      const { offset, limit } = parseBatchParams(req, body);
      const batchEnd = Math.min(offset + limit, allTargets.length);
      const batchTargets = allTargets.slice(offset, batchEnd);

      const athletesToUpsert: Record<string, unknown>[] = [];
      let changedCount = 0;
      let lastAthleteName: string | null = null;

      for (const target of batchTargets) {
        const name = String(target.row.PlayerName ?? "");
        lastAthleteName = name;
        const key = athleteKey(name, target.gender);
        const existing = existingByKey.get(key);
        const record = preserveManualFields(
          await buildAthleteRecordTitles(
            target.row,
            target.gender,
            existing,
          ),
          existing,
        );

        if (titlesChanged(existing, record)) {
          changedCount++;
          athletesToUpsert.push(record);
        }
      }

      if (athletesToUpsert.length > 0) {
        const { error: upsertErr } = await supabase.from("athletes").upsert(
          athletesToUpsert,
          { onConflict: "name,gender" },
        );
        if (upsertErr) throw upsertErr;
      }

      const processed = offset + batchTargets.length;
      const total = allTargets.length || TOTAL_ATHLETES;
      const done = processed >= total;

      return new Response(
        JSON.stringify({
          mode: "titles",
          athletesSynced: athletesToUpsert.length,
          athletesChanged: changedCount,
          titlesChanged: changedCount,
          processed,
          total,
          offset,
          done,
          currentAthlete: lastAthleteName,
          rankingWeek: remoteMeta.RankingWeek ?? null,
          rankingYear: remoteMeta.RankingYear ?? null,
          hasUpdates: changedCount > 0,
        }),
        {
          headers: {
            ...corsHeaders,
            "Content-Type": "application/json",
            "Connection": "keep-alive",
          },
        },
      );
    }

    const { offset, limit } = parseBatchParams(req, body);
    const batchEnd = Math.min(offset + limit, TOTAL_ATHLETES);
    const batchTargets = allTargets.slice(offset, batchEnd);

    const athletes: Record<string, unknown>[] = [];
    let changedCount = 0;
    let lastAthleteName: string | null = null;

    for (const target of batchTargets) {
      const keyGuess = athleteKey(
        String(target.row.PlayerName ?? ""),
        target.gender,
      );
      const existingGuess = existingByKey.get(keyGuess);
      const built = await buildAthleteRecordFull(target.row, target.gender);
      const key = athleteKey(
        String(built.name ?? ""),
        String(built.gender ?? ""),
      );
      const existing = existingByKey.get(key) ?? existingGuess;
      const record = preserveManualFields(built, existing);
      lastAthleteName = String(record.name ?? "");

      if (recordChangedFull(existing, record)) {
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
        mode: "full",
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
