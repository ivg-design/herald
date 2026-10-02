// Secrets are not in wrangler.toml, so `wrangler types` does not know them.
interface Env {
  RELAY_SECRET: string;
  PAIRING_SECRET?: string;
  PAIR_STARTS_PER_HOUR?: string;       // per client address
  PAIR_STARTS_GLOBAL_PER_HOUR?: string;
  MAX_DEVICES?: string;
  DEVICE_NOTIFICATIONS_PER_DAY?: string;
  DEVICE_QUEUE_MAX?: string;
  DEVICE_REQUESTS_PER_DAY?: string;
  DEVICE_AUDIO_UPLOADS_PER_DAY?: string;
  DEVICE_AUDIO_BYTES_PER_DAY?: string;
  DEVICE_POLL_SECONDS_PER_DAY?: string;
  REGISTER_PER_HOUR?: string;
}
