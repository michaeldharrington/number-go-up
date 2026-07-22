import { DurableObject } from "cloudflare:workers";

export interface HistoryPoint {
  ts: string; // ISO timestamp of the snapshot
  total: number;
}

const HOUR_MS = 60 * 60 * 1000;
const HISTORY_LEN = 24;

/**
 * The single global counter. The Worker always reaches it via
 * idFromName("global"), so exactly one instance exists worldwide.
 *
 * DO lifecycle notes:
 * - The object is created lazily on first access and may be evicted from
 *   memory at any time; `this.ctx.storage` is the only durable state.
 * - We cache `total` in memory purely to skip a storage read on the hot
 *   path; the constructor re-hydrates it via blockConcurrencyWhile, which
 *   guarantees no request runs before hydration completes.
 * - An alarm wakes the object every hour (even if evicted) to append a
 *   history snapshot. Alarms survive eviction, but a brand-new object has
 *   none scheduled, so both `read` and `increment` call ensureAlarm().
 *
 * Deliberately holds NO per-user state — that lives in KV so this object
 * never becomes a per-request bottleneck or a PII store.
 */
export class GlobalCounter extends DurableObject {
  private total = 0;

  constructor(ctx: DurableObjectState, env: unknown) {
    super(ctx, env as never);
    this.ctx.blockConcurrencyWhile(async () => {
      this.total = (await this.ctx.storage.get<number>("total")) ?? 0;
    });
  }

  /** Schedule the hourly history alarm if none is pending. */
  private async ensureAlarm(): Promise<void> {
    if ((await this.ctx.storage.getAlarm()) === null) {
      await this.ctx.storage.setAlarm(Date.now() + HOUR_MS);
    }
  }

  async read(): Promise<number> {
    await this.ensureAlarm();
    return this.total;
  }

  async increment(): Promise<number> {
    this.total += 1;
    // put() is coalesced and implicitly awaited before the response is
    // sent (output gate), so this is durable without blocking.
    await this.ctx.storage.put("total", this.total);
    await this.ensureAlarm();
    return this.total;
  }

  async history(): Promise<HistoryPoint[]> {
    return (await this.ctx.storage.get<HistoryPoint[]>("history")) ?? [];
  }

  /**
   * Hourly alarm: snapshot the current total into a rolling 24-entry
   * array. If the alarm fires late (or the object slept through several
   * hours), we still only append one point — gaps are acceptable for a
   * sparkline.
   */
  async alarm(): Promise<void> {
    const history =
      (await this.ctx.storage.get<HistoryPoint[]>("history")) ?? [];
    history.push({ ts: new Date().toISOString(), total: this.total });
    while (history.length > HISTORY_LEN) history.shift();
    await this.ctx.storage.put("history", history);
    await this.ctx.storage.setAlarm(Date.now() + HOUR_MS);
  }
}
