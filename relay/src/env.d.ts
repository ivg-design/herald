// Secrets are not in wrangler.toml, so `wrangler types` does not know them.
interface Env {
  RELAY_SECRET: string;
  PAIRING_SECRET?: string;
  PAIR_STARTS_PER_HOUR?: string;
}
