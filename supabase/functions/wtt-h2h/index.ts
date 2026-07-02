import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const WTT_HEADERS = {
  Accept: "application/json, text/plain, */*",
  Referer: "https://www.worldtabletennis.com/",
  Origin: "https://www.worldtabletennis.com",
  "User-Agent":
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
  ApiKey: "2bf8b222-532c-4c60-8ebe-eb6fdfebe84a",
};

const H2H_URL =
  "https://wttcmsapigateway-new.azure-api.net/ttu/Players/GetPlayersHeadToHead";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
};

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
    },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response(null, { headers: corsHeaders });
  }

  try {
    let player1 = "";
    let player2 = "";

    if (req.method === "POST") {
      const body = await req.json();
      player1 = String(body.player1 ?? body.Player1 ?? "");
      player2 = String(body.player2 ?? body.Player2 ?? "");
    } else {
      const url = new URL(req.url);
      player1 = url.searchParams.get("player1") ??
        url.searchParams.get("Player1") ?? "";
      player2 = url.searchParams.get("player2") ??
        url.searchParams.get("Player2") ?? "";
    }

    if (!player1 || !player2) {
      return jsonResponse({ error: "player1 e player2 obrigatórios" }, 400);
    }

    const apiUrl = new URL(H2H_URL);
    apiUrl.searchParams.set("Player1", player1);
    apiUrl.searchParams.set("Player2", player2);
    apiUrl.searchParams.set("EventId", "0");
    apiUrl.searchParams.set("MatchId", "0");
    apiUrl.searchParams.set("q", String(Date.now()));

    const response = await fetch(apiUrl, { headers: WTT_HEADERS });
    const payload = await response.json();

    return jsonResponse(payload, response.status);
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    return jsonResponse({ error: message }, 500);
  }
});
