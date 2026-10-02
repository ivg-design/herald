import { cloudflareTest } from "@cloudflare/vitest-pool-workers";
import { defineConfig } from "vitest/config";

export default defineConfig({
  plugins: [
    cloudflareTest({
      wrangler: { configPath: "./wrangler.toml" },
      miniflare: { bindings: { RELAY_SECRET: "test-relay-secret", MAX_DEVICES: "10000", PAIR_STARTS_PER_HOUR: "10000" } },
    }),
  ],
  test: { include: ["test/**/*.test.ts"] },
});
