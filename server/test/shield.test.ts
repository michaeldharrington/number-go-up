import { env, SELF } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { GlobalCounter } from "../src/counter";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    COUNTER: DurableObjectNamespace<GlobalCounter>;
  }
}

describe("GET /shield", () => {
  it("returns shields.io endpoint schema without requiring a client ID", async () => {
    const res = await SELF.fetch("https://example.com/shield");
    expect(res.status).toBe(200);
    const body = await res.json<Record<string, unknown>>();
    expect(body.schemaVersion).toBe(1);
    expect(body.label).toBe("click count");
    expect(typeof body.message).toBe("string");
  });

  it("shows the full current number with separators", async () => {
    // Seed the global DO directly, then read through the endpoint.
    const stub = env.COUNTER.get(env.COUNTER.idFromName("global"));
    for (let i = 0; i < 1500; i++) await stub.increment();

    const res = await SELF.fetch("https://example.com/shield");
    const body = await res.json<{ message: string }>();
    expect(body.message).toBe("1,500");
  });
});
