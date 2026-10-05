// The cloud-facing notification schema. A whitelist: anything not listed is refused with 400 and named, so no
// command, callback, script, shortcut, action, image or template can ride along.

export const MAX_BODY_BYTES = 32 * 1024;
export const MAX_NOTIFICATION_ID = 128;

/** Fields that are called out by name in the error because they are the ones an attacker would reach for. */
export const DANGEROUS = new Set([
  "command", "commands", "cmd", "script", "scripts", "shortcut", "shortcuts", "callback", "callbacks", "webhook",
  "buttons", "actions", "actionIds", "action", "reminder", "url", "audio", "image", "template", "layout",
  "followUp", "follow_up", "followup", "app", "appId", "path", "exec", "run", "open", "openApp", "snooze", "metadata", "accentColor", "templateName",
]);

/** A data: icon may be this large (decoded); the request body is allowed that much more than the normal limit. */
export const MAX_ICON_BYTES = 256 * 1024;
export const ICON_BODY_ALLOWANCE = Math.ceil(MAX_ICON_BYTES * 4 / 3) + 64;
const SOUND = /^[A-Za-z0-9][A-Za-z0-9 ._-]{0,39}$/;

const ALLOWED = new Set([
  "notificationId", "title", "subtitle", "body", "status", "project", "session", "task", "tool", "duration",
  "link", "group", "priority", "speak", "expectReply", "allowVoiceReply",
  "persistent", "timeoutSeconds", "sound", "voice", "speed", "presentation", "icon", "imageURL", "tags",
]);

export interface Speak { text?: string; voice?: string; speed?: number; lang?: string }
export interface Cleaned {
  title: string; subtitle?: string; body?: string; status?: string; project?: string; session?: string; task?: string;
  tool?: string; duration?: string; link?: string; group?: string; priority?: "low" | "normal" | "high" | "urgent";
  speak?: true | Speak; expectReply: boolean; allowVoiceReply?: boolean;
  persistent?: boolean; timeoutSeconds?: number; sound?: string; presentation?: "banner" | "voice" | "both";
  icon?: string; imageURL?: string; tags?: string[];
}

export type Validated =
  | { ok: true; notificationId?: string; value: Cleaned }
  | { ok: false; error: string; message: string; fields?: string[] };

const bad = (message: string, fields?: string[]): Validated => ({ ok: false, error: "invalid_request", message, fields });

function str(v: unknown, name: string, max: number): string | undefined | Validated {
  if (v === undefined || v === null) return undefined;
  if (typeof v !== "string") return bad(`${name} must be a string`, [name]);
  const t = v.trim();
  if (t.length > max) return bad(`${name} is longer than ${max} characters`, [name]);
  return t.length ? t : undefined;
}
const isBad = (x: unknown): x is Validated => typeof x === "object" && x !== null && "ok" in x;

export function validateNotification(input: unknown): Validated {
  if (typeof input !== "object" || input === null || Array.isArray(input)) return bad("the body must be a JSON object");
  const o = input as Record<string, unknown>;
  const rejected = Object.keys(o).filter((k) => !ALLOWED.has(k));
  if (rejected.length) {
    const named = rejected.filter((k) => DANGEROUS.has(k));
    return {
      ok: false,
      error: "forbidden_fields",
      fields: rejected,
      message:
        `rejected fields: ${rejected.join(", ")}. Cloud notifications carry text and presentation only` +
        (named.length ? ` (${named.join(", ")} would run or open something on the Mac and is never accepted)` : "") +
        `. Accepted fields: ${[...ALLOWED].join(", ")}.`,
    };
  }

  let notificationId: string | undefined;
  if (o.notificationId !== undefined) {
    if (typeof o.notificationId !== "string" || !/^[A-Za-z0-9._:-]{1,128}$/.test(o.notificationId)) {
      return bad(`notificationId must match [A-Za-z0-9._:-] and be at most ${MAX_NOTIFICATION_ID} characters`, ["notificationId"]);
    }
    notificationId = o.notificationId;
  }

  const title = str(o.title, "title", 200);
  if (isBad(title)) return title;
  if (!title) return bad("title is required", ["title"]);

  const out: Cleaned = { title, expectReply: false };
  for (const [k, max] of [["subtitle", 200], ["body", 8000], ["project", 100], ["session", 100], ["task", 100], ["tool", 100], ["group", 100]] as const) {
    const v = str(o[k], k, max);
    if (isBad(v)) return v;
    if (v !== undefined) (out as unknown as Record<string, unknown>)[k] = v;
  }

  const status = str(o.status, "status", 32);
  if (isBad(status)) return status;
  if (status !== undefined) {
    if (!/^[A-Za-z0-9_-]{1,32}$/.test(status)) return bad("status must be a short word (letters, digits, - or _)", ["status"]);
    out.status = status.toLowerCase();
  }

  if (o.duration !== undefined && o.duration !== null) {
    if (typeof o.duration === "number" && Number.isFinite(o.duration)) out.duration = String(o.duration);
    else {
      const d = str(o.duration, "duration", 40);
      if (isBad(d)) return d;
      out.duration = d;
    }
  }

  const link = str(o.link, "link", 2048);
  if (isBad(link)) return link;
  if (link !== undefined) {
    let u: URL;
    try { u = new URL(link); } catch { return bad("link must be an absolute https URL", ["link"]); }
    if (u.protocol !== "https:") return bad("link must be an https URL", ["link"]);
    out.link = u.toString();
  }

  if (o.priority !== undefined && o.priority !== null) {
    if (o.priority !== "low" && o.priority !== "normal" && o.priority !== "high" && o.priority !== "urgent") return bad('priority must be "low", "normal", "high" or "urgent"', ["priority"]);
    out.priority = o.priority;
  }

  if (o.expectReply !== undefined && o.expectReply !== null) {
    if (typeof o.expectReply !== "boolean") return bad("expectReply must be true or false", ["expectReply"]);
    out.expectReply = o.expectReply;
  }

  if (o.allowVoiceReply !== undefined && o.allowVoiceReply !== null) {
    if (typeof o.allowVoiceReply !== "boolean") return bad("allowVoiceReply must be true or false", ["allowVoiceReply"]);
    out.allowVoiceReply = o.allowVoiceReply;
  }

  if (o.persistent !== undefined && o.persistent !== null) {
    if (typeof o.persistent !== "boolean") return bad("persistent must be true or false", ["persistent"]);
    out.persistent = o.persistent;
  }
  if (o.timeoutSeconds !== undefined && o.timeoutSeconds !== null) {
    if (typeof o.timeoutSeconds !== "number" || !Number.isFinite(o.timeoutSeconds) || o.timeoutSeconds < 1 || o.timeoutSeconds > 3600) return bad("timeoutSeconds must be a number from 1 to 3600 (use persistent: true to stay until dismissed)", ["timeoutSeconds"]);
    out.timeoutSeconds = o.timeoutSeconds;
  }
  if (o.sound !== undefined && o.sound !== null) {
    if (typeof o.sound !== "string" || !SOUND.test(o.sound)) return bad('sound must be a system sound name such as "Glass", "default" or "none" (no paths)', ["sound"]);
    out.sound = o.sound;
  }
  if (o.presentation !== undefined && o.presentation !== null) {
    if (o.presentation !== "banner" && o.presentation !== "voice" && o.presentation !== "both") return bad('presentation must be "banner", "voice" or "both"', ["presentation"]);
    out.presentation = o.presentation;
  }

  if (o.icon !== undefined && o.icon !== null) {
    if (typeof o.icon !== "string") return bad("icon must be an https URL or a data: image", ["icon"]);
    const m = /^data:image\/(png|jpeg|gif|webp);base64,([A-Za-z0-9+/=]+)$/.exec(o.icon);
    if (m) {
      const bytes = Math.floor(m[2].length * 3 / 4) - (m[2].endsWith("==") ? 2 : m[2].endsWith("=") ? 1 : 0);
      if (bytes > MAX_ICON_BYTES) return bad(`icon is larger than ${MAX_ICON_BYTES / 1024} KB`, ["icon"]);
      out.icon = o.icon;
    } else {
      let u: URL;
      try { u = new URL(o.icon); } catch { return bad("icon must be an https URL or a data:image/png|jpeg|gif|webp;base64 image", ["icon"]); }
      if (u.protocol !== "https:" || o.icon.length > 2048) return bad("icon must be an https URL (up to 2048 characters) or a data: image", ["icon"]);
      out.icon = u.toString();
    }
  }
  const imageURL = str(o.imageURL, "imageURL", 2048);
  if (isBad(imageURL)) return imageURL;
  if (imageURL !== undefined) {
    let u: URL;
    try { u = new URL(imageURL); } catch { return bad("imageURL must be an absolute https URL", ["imageURL"]); }
    if (u.protocol !== "https:") return bad("imageURL must be an https URL", ["imageURL"]);
    out.imageURL = u.toString();
  }
  if (o.tags !== undefined && o.tags !== null) {
    if (!Array.isArray(o.tags) || o.tags.length > 10 || !o.tags.every((t) => typeof t === "string" && /^[^\s,][^,]{0,31}$/.test(t.trim()))) {
      return bad("tags must be up to 10 short strings (at most 32 characters, no commas)", ["tags"]);
    }
    const tags = [...new Set(o.tags.map((t: string) => t.trim()))];
    if (tags.length) out.tags = tags;
  }

  // speak: true, a string (the text to say), or {text, voice, speed, lang}. voice and speed beside it are the same as inside.
  let speak: Speak | true | undefined;
  if (o.speak !== undefined && o.speak !== null && o.speak !== false) {
    if (o.speak === true) speak = true;
    else if (typeof o.speak === "string") {
      const text = str(o.speak, "speak", 2000);
      if (isBad(text)) return text;
      speak = text ? { text } : true;
    } else if (typeof o.speak === "object" && !Array.isArray(o.speak)) {
      const s = o.speak as Record<string, unknown>;
      const extra = Object.keys(s).filter((k) => !["text", "voice", "speed", "lang"].includes(k));
      if (extra.length) return { ok: false, error: "forbidden_fields", fields: extra.map((k) => "speak." + k), message: `rejected fields: ${extra.map((k) => "speak." + k).join(", ")}. speak accepts text, voice, speed, lang.` };
      const sp: Speak = {};
      const text = str(s.text, "speak.text", 2000);
      if (isBad(text)) return text;
      if (text) sp.text = text;
      if (s.voice !== undefined) {
        if (typeof s.voice !== "string" || !/^[A-Za-z0-9_]{1,40}$/.test(s.voice)) return bad("speak.voice must be a voice name such as af_heart", ["speak.voice"]);
        sp.voice = s.voice;
      }
      if (s.speed !== undefined) {
        if (typeof s.speed !== "number" || !(s.speed >= 0.5 && s.speed <= 2)) return bad("speak.speed must be between 0.5 and 2", ["speak.speed"]);
        sp.speed = s.speed;
      }
      if (s.lang !== undefined) {
        if (typeof s.lang !== "string" || !/^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})?$/.test(s.lang)) return bad("speak.lang must be a language code such as en-us", ["speak.lang"]);
        sp.lang = s.lang;
      }
      speak = sp;
    } else return bad("speak must be true, the text to say, or an object {text, voice, speed, lang}", ["speak"]);
  }
  let voice: string | undefined, speed: number | undefined;
  if (o.voice !== undefined && o.voice !== null) {
    if (typeof o.voice !== "string" || !/^[A-Za-z0-9_]{1,40}$/.test(o.voice)) return bad("voice must be a voice name such as af_heart", ["voice"]);
    voice = o.voice;
  }
  if (o.speed !== undefined && o.speed !== null) {
    if (typeof o.speed !== "number" || !(o.speed >= 0.5 && o.speed <= 2)) return bad("speed must be between 0.5 and 2", ["speed"]);
    speed = o.speed;
  }
  // An explicit speak: false wins over everything that would imply speech (voice, speed, presentation).
  if (speak === undefined && o.speak !== false && (voice !== undefined || speed !== undefined || out.presentation === "voice" || out.presentation === "both")) speak = true;
  if (speak !== undefined) {
    if (voice !== undefined || speed !== undefined) {
      const base: Speak = speak === true ? {} : speak;
      speak = { ...base, ...(voice !== undefined && base.voice === undefined ? { voice } : {}), ...(speed !== undefined && base.speed === undefined ? { speed } : {}) };
      if (Object.keys(speak).length === 0) speak = true;
    }
    out.speak = speak;
  }
  return { ok: true, notificationId, value: out };
}
