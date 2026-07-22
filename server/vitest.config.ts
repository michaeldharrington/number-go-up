import { defineWorkersConfig } from "@cloudflare/vitest-pool-workers/config";

export default defineWorkersConfig({
  test: {
    poolOptions: {
      workers: {
        wrangler: { configPath: "./wrangler.toml" },
        // Real KV/DO ids aren't needed under Miniflare.
        miniflare: {
          kvNamespaces: ["RATE_LIMIT"],
        },
      },
    },
  },
});
