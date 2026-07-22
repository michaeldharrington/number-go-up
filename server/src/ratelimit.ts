/**
 * Layered rate limiting, all in KV (never the Durable Object):
 *
 *  1. user:{clientId}  → ISO timestamp of last click, TTL 1h.
 *     Present ⇒ that user already clicked this hour.
 *  2. ip:{sha256(ip)}  → JSON { count, resetAt }, expires at resetAt.
 *     Caps a single IP at IP_HOURLY_CAP clicks/hour across all client IDs,
 *     so spinning up fresh UUIDs doesn't help much.
 *  3. clicks:{clientId} → lifetime click count, no TTL (for "yourClicks").
 *
 * KV is eventually consistent (~60s propagation), so a determined user can
 * squeeze an extra click in at the edge boundary. That's fine — this is a
 * toy counter, not a billing system. The DO stays authoritative for the
 * total; KV only throttles.
 */

export const CLICK_INTERVAL_S = 3600;
export const IP_HOURLY_CAP = 5;

export interface RateLimitResult {
  allowed: boolean;
  /** ISO timestamp when the caller may click again; null = now. */
  nextClickAt: string | null;
}

interface IpBucket {
  count: number;
  resetAt: string;
}

/** Hex sha256 of the connecting IP so raw IPs never land in KV. */
export async function hashIp(ip: string): Promise<string> {
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(ip),
  );
  return [...new Uint8Array(digest)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

/** Read-only check — used by GET /count to report nextClickAt. */
export async function checkUserLimit(
  kv: KVNamespace,
  clientId: string,
  now: Date,
): Promise<RateLimitResult> {
  const lastClick = await kv.get(`user:${clientId}`);
  if (lastClick === null) return { allowed: true, nextClickAt: null };
  const next = new Date(
    new Date(lastClick).getTime() + CLICK_INTERVAL_S * 1000,
  );
  // The KV TTL may outlive the logical window by propagation lag; if the
  // computed time is already past, treat the user as allowed.
  if (next <= now) return { allowed: true, nextClickAt: null };
  return { allowed: false, nextClickAt: next.toISOString() };
}

export async function checkIpLimit(
  kv: KVNamespace,
  ipHash: string,
  now: Date,
): Promise<RateLimitResult> {
  const bucket = await kv.get<IpBucket>(`ip:${ipHash}`, "json");
  if (bucket === null || new Date(bucket.resetAt) <= now)
    return { allowed: true, nextClickAt: null };
  if (bucket.count < IP_HOURLY_CAP) return { allowed: true, nextClickAt: null };
  return { allowed: false, nextClickAt: bucket.resetAt };
}

/**
 * Record a successful click: stamp the user key, bump the IP bucket, bump
 * the lifetime count. Returns { yourClicks, nextClickAt } for the response.
 */
export async function recordClick(
  kv: KVNamespace,
  clientId: string,
  ipHash: string,
  now: Date,
): Promise<{ yourClicks: number; nextClickAt: string }> {
  const nextClickAt = new Date(
    now.getTime() + CLICK_INTERVAL_S * 1000,
  ).toISOString();

  const bucket = await kv.get<IpBucket>(`ip:${ipHash}`, "json");
  const live = bucket !== null && new Date(bucket.resetAt) > now;
  const newBucket: IpBucket = live
    ? { count: bucket.count + 1, resetAt: bucket.resetAt }
    : { count: 1, resetAt: nextClickAt };
  // Keep the bucket's original expiry — re-putting must not extend the
  // window, or 5 spaced clicks would lock the IP out forever.
  const expiration = Math.ceil(new Date(newBucket.resetAt).getTime() / 1000);

  const yourClicks =
    parseInt((await kv.get(`clicks:${clientId}`)) ?? "0", 10) + 1;

  await Promise.all([
    kv.put(`user:${clientId}`, now.toISOString(), {
      expirationTtl: CLICK_INTERVAL_S,
    }),
    kv.put(`ip:${ipHash}`, JSON.stringify(newBucket), { expiration }),
    kv.put(`clicks:${clientId}`, String(yourClicks)),
  ]);

  return { yourClicks, nextClickAt };
}

export async function getLifetimeClicks(
  kv: KVNamespace,
  clientId: string,
): Promise<number> {
  return parseInt((await kv.get(`clicks:${clientId}`)) ?? "0", 10);
}
