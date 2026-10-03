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
