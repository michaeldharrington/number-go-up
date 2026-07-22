import { env } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import {
  checkIpLimit,
  checkUserLimit,
  CLICK_INTERVAL_S,
  hashIp,
  IP_HOURLY_CAP,
  recordClick,
} from "../src/ratelimit";

// Each test uses a unique clientId/IP so tests don't share KV state.
const uuid = (n: number) =>
  `00000000-0000-4000-8000-${String(n).padStart(12, "0")}`;

declare module "cloudflare:test" {
  interface ProvidedEnv {
    RATE_LIMIT: KVNamespace;
  }
}

describe("user rate limit", () => {
  it("allows a first-time user", async () => {
    const res = await checkUserLimit(env.RATE_LIMIT, uuid(1), new Date());
    expect(res).toEqual({ allowed: true, nextClickAt: null });
  });

  it("blocks a second click within the hour and reports nextClickAt", async () => {
    const now = new Date();
    await recordClick(env.RATE_LIMIT, uuid(2), await hashIp("10.0.0.2"), now);

    const later = new Date(now.getTime() + 30 * 60 * 1000); // +30min
    const res = await checkUserLimit(env.RATE_LIMIT, uuid(2), later);
    expect(res.allowed).toBe(false);
    expect(res.nextClickAt).toBe(
      new Date(now.getTime() + CLICK_INTERVAL_S * 1000).toISOString(),
    );
  });

  it("allows again once the interval has logically elapsed", async () => {
    const now = new Date();
    await recordClick(env.RATE_LIMIT, uuid(3), await hashIp("10.0.0.3"), now);

    // KV TTL hasn't expired in Miniflare, but the logical window has.
    const later = new Date(now.getTime() + (CLICK_INTERVAL_S + 1) * 1000);
    const res = await checkUserLimit(env.RATE_LIMIT, uuid(3), later);
    expect(res).toEqual({ allowed: true, nextClickAt: null });
  });
});

describe("IP rate limit", () => {
  it("caps distinct client IDs behind one IP at IP_HOURLY_CAP/hour", async () => {
    const now = new Date();
    const ipHash = await hashIp("10.0.0.4");

    for (let i = 0; i < IP_HOURLY_CAP; i++) {
      const check = await checkIpLimit(env.RATE_LIMIT, ipHash, now);
      expect(check.allowed).toBe(true);
      await recordClick(env.RATE_LIMIT, uuid(100 + i), ipHash, now);
    }

    const blocked = await checkIpLimit(env.RATE_LIMIT, ipHash, now);
    expect(blocked.allowed).toBe(false);
    expect(blocked.nextClickAt).not.toBeNull();
  });

  it("does not extend the window on subsequent clicks", async () => {
    const t0 = new Date();
    const ipHash = await hashIp("10.0.0.5");
    await recordClick(env.RATE_LIMIT, uuid(200), ipHash, t0);

    // Second click 30min later must keep the reset anchored at t0+1h.
    const t1 = new Date(t0.getTime() + 30 * 60 * 1000);
    await recordClick(env.RATE_LIMIT, uuid(201), ipHash, t1);

    const afterWindow = new Date(t0.getTime() + (CLICK_INTERVAL_S + 1) * 1000);
    const res = await checkIpLimit(env.RATE_LIMIT, ipHash, afterWindow);
    expect(res.allowed).toBe(true);
  });
});

describe("lifetime clicks", () => {
  it("accumulates across clicks", async () => {
    const ipHash = await hashIp("10.0.0.6");
    const r1 = await recordClick(
      env.RATE_LIMIT, uuid(300), ipHash, new Date(),
    );
    const r2 = await recordClick(
      env.RATE_LIMIT, uuid(300), ipHash, new Date(Date.now() + 2 * 3600 * 1000),
    );
    expect(r1.yourClicks).toBe(1);
    expect(r2.yourClicks).toBe(2);
  });
});
