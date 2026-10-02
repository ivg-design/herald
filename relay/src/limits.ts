// Per-device limits. Every paired Mac has its own Durable Object, so every counter below is per device, never global: one noisy or
// hostile Mac cannot use up another Mac's allowance. The defaults are sized for the shared hosted relay (docs/CLOUD.md,
// "Free plan budget"); a relay of your own can raise them with Worker vars (wrangler.toml [vars] or `--var NAME:value`).

export interface Limits {
  notificationsPerDay: number;   // DEVICE_NOTIFICATIONS_PER_DAY
  queueMax: number;              // DEVICE_QUEUE_MAX: undelivered notifications waiting for the Mac
  requestsPerDay: number;        // DEVICE_REQUESTS_PER_DAY: requests that reach the device's mailbox (503 after)
  audioUploadsPerDay: number;    // DEVICE_AUDIO_UPLOADS_PER_DAY
  audioBytesPerDay: number;      // DEVICE_AUDIO_BYTES_PER_DAY
  pollSecondsPerDay: number;     // DEVICE_POLL_SECONDS_PER_DAY: the mailbox is awake while a long-poll waits
  ttlMs: number;                 // QUEUE_TTL_HOURS: how long an undelivered notification waits for the Mac
  bodyBytes: number;             // MAX_BODY_BYTES: largest notify request
  ratePerKey: number;            // RATE_LIMIT_PER_KEY: notifications per 10 minutes per agent key
}

export const DEFAULT_LIMITS: Limits = {
  notificationsPerDay: 500,
  queueMax: 100,
  requestsPerDay: 5000,
  audioUploadsPerDay: 40,
  audioBytesPerDay: 20 * 1024 * 1024,
  pollSecondsPerDay: 3000,
  ttlMs: 24 * 3600_000,
  bodyBytes: 32 * 1024,
  ratePerKey: 60,
};

const VARS: Record<keyof Limits, string> = {
  notificationsPerDay: "DEVICE_NOTIFICATIONS_PER_DAY",
  queueMax: "DEVICE_QUEUE_MAX",
  requestsPerDay: "DEVICE_REQUESTS_PER_DAY",
  audioUploadsPerDay: "DEVICE_AUDIO_UPLOADS_PER_DAY",
  audioBytesPerDay: "DEVICE_AUDIO_BYTES_PER_DAY",
  pollSecondsPerDay: "DEVICE_POLL_SECONDS_PER_DAY",
  ttlMs: "QUEUE_TTL_HOURS",
  bodyBytes: "MAX_BODY_BYTES",
  ratePerKey: "RATE_LIMIT_PER_KEY",
};

/** The limits in force: a Worker var when it is a positive number, otherwise the default. */
export function limitsFor(env: unknown): Limits {
  const e = (env ?? {}) as Record<string, unknown>;
  const out = { ...DEFAULT_LIMITS };
  for (const k of Object.keys(VARS) as (keyof Limits)[]) {
    const n = Number(e[VARS[k]]);
    if (Number.isFinite(n) && n > 0) out[k] = Math.floor(k === "ttlMs" ? n * 3600_000 : n);
  }
  return out;
}
