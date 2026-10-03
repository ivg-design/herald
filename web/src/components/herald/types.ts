// The page runs Herald. Every demo "sends" to the page's own Herald through this API instead of rendering a private mock.
// Implemented by HeraldHost (src/components/herald/HeraldHost.tsx); consumed via useHerald().

export type HeraldIcon = "herald" | "ci" | "mail" | "ae" | "claude" | "web" | "agent";
export type HeraldRole = "open" | "deploy" | "snooze" | "dismiss";

export interface HeraldButton {
  label: string;
  role: HeraldRole;
  primary?: boolean;
  /** What "Open" pretends to open (shown in the outcome line). */
  url?: string;
}

export interface HeraldSend {
  /** Sender id. Same `app` = same stack: the banner does not multiply, the counter goes up. */
  app: string;
  /** Display name of the sender, e.g. "CI Bot". Defaults to `app`. */
  appName?: string;
  icon?: HeraldIcon;
  title: string;
  body?: string;
  buttons?: HeraldButton[];
  /** Text of the inline Yes/Cancel strip shown when a `deploy` button is pressed. */
  confirm?: string;
  /** Cloud banner: a reply field with Record (3 s fake recording, then this transcript) and Send. */
  reply?: { transcript: string };
  /** Attach a voice: a pre-rendered Kokoro sample under /audio (e.g. "voice-sample"). The card shows a Play button; nothing plays on its own. */
  speak?: boolean | string;
  /** Snooze demo: seconds until the banner returns (default 3) and the label shown ("9:00"). */
  snooze?: { seconds?: number; label?: string };
}

export interface HeraldQuiet {
  /** Minutes after midnight, e.g. 22*60 and 7*60. Wraps past midnight. */
  from: number;
  to: number;
  muteSound: boolean;
  muteVoice: boolean;
  /** Hold banners until the window ends (they land in the pill as "held"). */
  hold: boolean;
  /** Demo clock override, minutes after midnight; undefined = real local time. */
  pretendNow?: number;
}

export interface HeraldState {
  /** Banners currently on screen (cards, not stack members). */
  onScreen: number;
  /** Stack members on screen (sum of counters). */
  pending: number;
  /** Dismissed or acted on: "kept in History". */
  history: number;
  snoozed: number;
  held: number;
  /** Kept for compatibility: always true (voice samples are pre-rendered, never synthesized in the browser). */
  voice: boolean;
  /** True while a card's voice sample is playing. */
  speaking: boolean;
  quiet: HeraldQuiet;
  /** True while the hero dock is on screen, i.e. banners render in-flow in the hero rather than in the fixed overlay. */
  docked: boolean;
}

export interface HeraldApi extends HeraldState {
  /** Show a banner. Returns its id. Respects quiet hours (held) and the voice switch (speak). */
  send(n: HeraldSend): string;
  dismissAll(): void;
  /** Expand the fixed overlay stack (used by the header bell and the pill). */
  show(): void;
  setVoice(on: boolean): void;
  setQuiet(patch: Partial<HeraldQuiet>): void;
  /** True if the given minute-of-day is inside the quiet window. */
  isQuiet(minute?: number): boolean;
  /** The current demo minute-of-day (pretendNow or the real clock). */
  nowMinute(): number;
}
