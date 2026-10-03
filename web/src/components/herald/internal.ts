"use client";
// Internals shared by HeraldHost, PageStack, Header and Hero. Not part of the public HeraldApi contract.
import { createContext, useContext } from "react";
import type { HeraldApi, HeraldButton, HeraldIcon, HeraldSend } from "./types";

export interface StackItem { id: string; title: string; body: string }

export interface HeraldCardModel {
  id: string;
  app: string;
  appName: string;
  icon: HeraldIcon;
  items: StackItem[];
  buttons: HeraldButton[];
  confirm?: string;
  reply?: { transcript: string };
  snooze?: { seconds?: number; label?: string };
  /** Voice sample name (/audio/<name>.mp3); set when the send had `speak`. */
  speak?: string;
  /** Index among the starting banners (drives the 140 ms entrance stagger); undefined for later sends. */
  seedIndex?: number;
}

export interface HeraldInternals extends HeraldApi {
  /** Increments on every send (the header bell rings when it changes). */
  ring: number;
  cards: HeraldCardModel[];
  /** Fixed overlay shows cards (true) or the compact pill (false). */
  expanded: boolean;
  /** "arrival": only the just-updated card slides in (4 s); "full": header, all cards, Dismiss all (bell hover/click). */
  overlayMode: "arrival" | "full";
  /** Card id shown in arrival mode. */
  arrivalId: string | null;
  speakingId: string | null;
  snoozingIds: string[];
  /** "07:00": when held banners are released. */
  heldUntil: string;
  /** Place a starting banner (appended, no overlay expansion, no ring). */
  seed(n: HeraldSend): string;
  /** Play / stop the card's pre-rendered voice sample (one at a time, only on click). */
  playVoice(id: string): void;
  stopVoice(): void;
  closeCard(id: string): void;
  dismissItem(cardId: string, itemId: string): void;
  setSnoozing(id: string, on: boolean): void;
  /** Release held banners ("Show anyway"). */
  showHeld(): void;
  compact(): void;
  /** Header bell: toggle (pin) the overlay. */
  toggle(): void;
  /** No-op: the page has no dock. */
  setDocked(on?: boolean): void;
  setHold(kind: "hover" | "focus", on: boolean): void;
}

export const HeraldInternalContext = createContext<HeraldInternals | null>(null);

export function useHeraldInternal(): HeraldInternals {
  const v = useContext(HeraldInternalContext);
  if (!v) throw new Error("needs <HeraldHost> above it");
  return v;
}
