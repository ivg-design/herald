"use client";
// One shared audio element for every pre-rendered voice sample on the page. Plays only when a caller asks (a click),
// one at a time. No speechSynthesis: the system voice is never used.
import { useSyncExternalStore } from "react";
import { asset } from "@/lib/config";

let audio: HTMLAudioElement | null = null;
let playingKey: string | null = null;
const subs = new Set<() => void>();
const set = (k: string | null) => {
  playingKey = k;
  subs.forEach((f) => f());
};

export const sampleName = (s: true | string) => (s === true ? "voice-sample" : s);

export function stopVoice() {
  audio?.pause();
  audio = null;
  set(null);
}

/** Play /audio/<name>.mp3 on behalf of `key` (any string identifying the caller). Replaces whatever was playing. */
export function playVoice(key: string, name: string) {
  stopVoice();
  const a = new Audio();
  a.preload = "none";
  const reset = () => {
    if (audio === a) {
      audio = null;
      set(null);
    }
  };
  a.addEventListener("ended", reset);
  a.addEventListener("error", reset);
  a.src = asset(`/audio/${name}.mp3`);
  audio = a;
  set(key);
  a.play().catch(reset);
}

export function usePlayingKey(): string | null {
  return useSyncExternalStore(
    (f) => {
      subs.add(f);
      return () => void subs.delete(f);
    },
    () => playingKey,
    () => null,
  );
}

/** Live position of the shared sample element (0/0 when nothing is loaded). */
export function getPlayback(): { currentTime: number; duration: number } {
  const d = audio?.duration;
  return { currentTime: audio?.currentTime ?? 0, duration: d && Number.isFinite(d) ? d : 0 };
}

const waves = new Map<string, Promise<number[]>>();

/** Decode /audio/<sample>.mp3 (decoding makes no sound) into `bars` RMS values normalised 0-1. Cached per sample. */
export function loadWaveform(sample: string, bars = 96): Promise<number[]> {
  const hit = waves.get(sample);
  if (hit) return hit;
  const job = (async () => {
    const Ctx = typeof window === "undefined" ? undefined : window.AudioContext ?? (window as unknown as { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
    if (!Ctx) throw new Error("no AudioContext");
    const res = await fetch(asset(`/audio/${sample}.mp3`));
    if (!res.ok) throw new Error(`audio ${res.status}`);
    const ctx = new Ctx();
    try {
      const buf = await ctx.decodeAudioData(await res.arrayBuffer());
      const ch = buf.getChannelData(0);
      const size = Math.max(1, Math.floor(ch.length / bars));
      const out: number[] = [];
      for (let i = 0; i < bars; i++) {
        let sum = 0;
        const from = i * size, to = Math.min(ch.length, from + size);
        for (let j = from; j < to; j++) sum += ch[j] * ch[j];
        out.push(Math.sqrt(sum / Math.max(1, to - from)));
      }
      const max = Math.max(...out, 1e-6);
      return out.map((v) => v / max);
    } finally {
      void ctx.close();
    }
  })();
  job.catch(() => waves.delete(sample));
  waves.set(sample, job);
  return job;
}
