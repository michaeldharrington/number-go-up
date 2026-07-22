import { env, runInDurableObject } from "cloudflare:test";
import { describe, expect, it } from "vitest";
import type { GlobalCounter } from "../src/counter";

declare module "cloudflare:test" {
  interface ProvidedEnv {
    COUNTER: DurableObjectNamespace<GlobalCounter>;
  }
}

describe("GlobalCounter DO", () => {
  it("starts at zero", async () => {
    const stub = env.COUNTER.get(env.COUNTER.idFromName("test-zero"));
    expect(await stub.read()).toBe(0);
  });

  it("increments and persists", async () => {
    const stub = env.COUNTER.get(env.COUNTER.idFromName("test-inc"));
    expect(await stub.increment()).toBe(1);
    expect(await stub.increment()).toBe(2);
    expect(await stub.read()).toBe(2);

    // Verify the value actually hit durable storage, not just memory.
    await runInDurableObject(stub, async (_instance, state) => {
      expect(await state.storage.get("total")).toBe(2);
    });
  });

  it("alarm appends a history point and caps at 24", async () => {
    const stub = env.COUNTER.get(env.COUNTER.idFromName("test-history"));
    await stub.increment();

    await runInDurableObject(stub, async (instance: GlobalCounter) => {
      // Fire the alarm 30 times; only the last 24 snapshots survive.
      for (let i = 0; i < 30; i++) await instance.alarm();
    });

    const history = await stub.history();
    expect(history).toHaveLength(24);
    expect(history.at(-1)?.total).toBe(1);
  });

  it("schedules an hourly alarm on first read", async () => {
    const stub = env.COUNTER.get(env.COUNTER.idFromName("test-alarm"));
    await stub.read();
    await runInDurableObject(stub, async (_instance, state) => {
      expect(await state.storage.getAlarm()).not.toBeNull();
    });
  });
});
