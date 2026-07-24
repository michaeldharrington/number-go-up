import type { GlobalCounter } from "./counter";
import {
  checkIpLimit,
  checkUserLimit,
  getLifetimeClicks,
  hashIp,
  recordClick,
} from "./ratelimit";

export { GlobalCounter } from "./counter";

export interface Env {
  COUNTER: DurableObjectNamespace<GlobalCounter>;
  RATE_LIMIT: KVNamespace;
}

const CORS_HEADERS: Record<string, string> = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
  "Access-Control-Allow-Headers": "Content-Type, X-Client-Id",
  "Access-Control-Max-Age": "86400",
};

const UUID_RE =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

function json(
  body: unknown,
  status = 200,
  extra: Record<string, string> = {},
): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Content-Type": "application/json",
      ...CORS_HEADERS,
      ...extra,
    },
  });
}

/** The one global counter instance. */
function counter(env: Env) {
  return env.COUNTER.get(env.COUNTER.idFromName("global"));
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    const url = new URL(request.url);

    if (request.method === "OPTIONS")
      return new Response(null, { status: 204, headers: CORS_HEADERS });

    // /history is anonymous — no client ID required.
    if (request.method === "GET" && url.pathname === "/history") {
      const history = await counter(env).history();
      return json({ history }, 200, {
        "Cache-Control": "public, max-age=60",
      });
    }

    // Anonymous shields.io endpoint badge (README "current number").
    // https://shields.io/badges/endpoint-badge
    if (request.method === "GET" && url.pathname === "/shield") {
      const total = await counter(env).read();
      return json(
        {
          schemaVersion: 1,
          label: "click count",
          message: total.toLocaleString("en-US"), // full number: "8,400,123"
          color: "brightgreen",
        },
        200,
        { "Cache-Control": "public, max-age=60" },
      );
    }

    const clientId = request.headers.get("X-Client-Id");
    if (!clientId || !UUID_RE.test(clientId))
      return json(
        { error: "Missing or malformed X-Client-Id header (expected UUID)" },
        400,
      );

    const now = new Date();

    if (request.method === "GET" && url.pathname === "/count") {
      const [total, yourClicks, userLimit] = await Promise.all([
        counter(env).read(),
        getLifetimeClicks(env.RATE_LIMIT, clientId),
        checkUserLimit(env.RATE_LIMIT, clientId, now),
      ]);
      // max-age=5 lets the edge absorb the polling herd; 5s of staleness
      // is invisible next to the 60s client poll interval.
      return json({ total, yourClicks, nextClickAt: userLimit.nextClickAt }, 200, {
        "Cache-Control": "public, max-age=5",
      });
    }

    if (request.method === "POST" && url.pathname === "/click") {
      const userLimit = await checkUserLimit(env.RATE_LIMIT, clientId, now);
      if (!userLimit.allowed)
        return json(
          { error: "You can only click once per hour", nextClickAt: userLimit.nextClickAt },
          429,
        );

      // Workers always see CF-Connecting-IP in production; fall back for
      // local dev where it may be absent.
      const ip = request.headers.get("CF-Connecting-IP") ?? "127.0.0.1";
      const ipHash = await hashIp(ip);
      const ipLimit = await checkIpLimit(env.RATE_LIMIT, ipHash, now);
      if (!ipLimit.allowed)
        return json(
          { error: "Too many clicks from this network", nextClickAt: ipLimit.nextClickAt },
          429,
        );

      // Order matters: bump the DO first, then record the rate-limit keys.
      // If KV writes fail the user gets a free retry — harmless. The
      // reverse order could eat a click without counting it.
      const total = await counter(env).increment();
      const { yourClicks, nextClickAt } = await recordClick(
        env.RATE_LIMIT,
        clientId,
        ipHash,
        now,
      );
      return json({ total, yourClicks, nextClickAt });
    }

    return json({ error: "Not found" }, 404);
  },
} satisfies ExportedHandler<Env>;
