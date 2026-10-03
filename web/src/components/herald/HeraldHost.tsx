"use client";

import { useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import { AnimatePresence } from "framer-motion";
import { playVoice, sampleName, stopVoice, usePlayingKey } from "./voice";
import LiveBanner from "@/components/mock/LiveBanner";
import { HeraldContext } from "./useHerald";
import { HeraldInternalContext, type HeraldCardModel, type HeraldInternals } from "./internal";
import { useHeraldInternal } from "./internal";
import type { HeraldQuiet, HeraldSend } from "./types";

const DEFAULT_QUIET: HeraldQuiet = { from: 22 * 60, to: 7 * 60, muteSound: true, muteVoice: true, hold: false };
const hhmm = (m: number) => `${String(Math.floor(m / 60)).padStart(2, "0")}:${String(m % 60).padStart(2, "0")}`;
const inWindow = (m: number, from: number, to: number) => (from <= to ? m >= from && m < to : m >= from || m < to);

type Held = HeraldSend & { id: string };

/**
 * The page's Herald. Owns the one list of banner cards, history/snoozed/held counters, pre-rendered voice samples and quiet
 * hours. HeroDock (in-flow, hero) and PageStack (fixed overlay) are two views of this same list.
 */
export function HeraldHost({ children }: { children: ReactNode }) {
  const [cards, setCardsState] = useState<HeraldCardModel[]>([]);
  const [held, setHeldState] = useState<Held[]>([]);
  const [history, setHistory] = useState(0);
  const [snoozingIds, setSnoozingIds] = useState<string[]>([]);
  const [quiet, setQuietState] = useState<HeraldQuiet>(DEFAULT_QUIET);
  const [docked, setDockedState] = useState(true);
  const [expanded, setExpandedState] = useState(false);
  const expandedRef = useRef(false);
  const setExpanded = useCallback((on: boolean) => {
    expandedRef.current = on;
    setExpandedState(on);
  }, []);
  const [ring, setRing] = useState(0);

  const cardsRef = useRef<HeraldCardModel[]>([]);
  const heldRef = useRef<Held[]>([]);
  const quietRef = useRef<HeraldQuiet>(DEFAULT_QUIET);
  const dockedRef = useRef(true);
  const hoverRef = useRef(false);
  const focusRef = useRef(false);
  const pinnedRef = useRef(false);
  const seq = useRef(0);
  const seeds = useRef(0);
  const timer = useRef<number | undefined>(undefined);

  const setCards = useCallback((next: HeraldCardModel[]) => {
    cardsRef.current = next;
    setCardsState(next);
  }, []);
  const setHeld = useCallback((next: Held[]) => {
    heldRef.current = next;
    setHeldState(next);
  }, []);

  const nowMinute = useCallback(() => {
    const p = quietRef.current.pretendNow;
    if (p !== undefined) return p;
    const d = new Date();
    return d.getHours() * 60 + d.getMinutes();
  }, []);
  const isQuiet = useCallback(
    (minute?: number) => inWindow(minute ?? nowMinute(), quietRef.current.from, quietRef.current.to),
    [nowMinute],
  );

  /* ---- overlay mode ---- */
  const expandFor = useCallback((ms: number) => {
    setExpanded(true);
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      if (!hoverRef.current && !focusRef.current && !pinnedRef.current) setExpanded(false);
    }, ms);
  }, [setExpanded]);
  const compact = useCallback(() => {
    pinnedRef.current = false;
    window.clearTimeout(timer.current);
    setExpanded(false);
  }, [setExpanded]);
  const setHold = useCallback((kind: "hover" | "focus", on: boolean) => {
    (kind === "hover" ? hoverRef : focusRef).current = on;
    window.clearTimeout(timer.current);
    if (!on && !hoverRef.current && !focusRef.current) {
      timer.current = window.setTimeout(() => {
        if (!pinnedRef.current) setExpanded(false);
      }, 1500);
    }
  }, [setExpanded]);
  const setDocked = useCallback((on: boolean) => {
    dockedRef.current = on;
    pinnedRef.current = false;
    setDockedState(on);
    window.clearTimeout(timer.current);
    setExpanded(false);
  }, [setExpanded]);
  const show = useCallback(() => {
    if (hoverRef.current || focusRef.current) {
      window.clearTimeout(timer.current);
      setExpanded(true);
    } else expandFor(6000);
  }, [expandFor, setExpanded]);

  const toggle = useCallback(() => {
    if (dockedRef.current) {
      document.getElementById("top")?.scrollIntoView({ behavior: "smooth", block: "start" });
      return;
    }
    if (expandedRef.current && pinnedRef.current) compact();
    else {
      // Click pins the overlay open (also when it was only open from hovering the bell).
      pinnedRef.current = true;
      window.clearTimeout(timer.current);
      setExpanded(true);
    }
  }, [compact, setExpanded]);

  useEffect(() => {
    const onDown = (e: PointerEvent) => {
      if (!expandedRef.current) return;
      const t = e.target as Element | null;
      if (t?.closest?.(".hb-overlay, .hb-bell")) return;
      compact();
    };
    window.addEventListener("pointerdown", onDown);
    return () => window.removeEventListener("pointerdown", onDown);
  }, [compact]);

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => e.key === "Escape" && compact();
    window.addEventListener("keydown", onKey);
    return () => {
      window.removeEventListener("keydown", onKey);
      window.clearTimeout(timer.current);
    };
  }, [compact]);

  /* ---- voice: pre-rendered samples, played only on an explicit click ---- */
  const stop = useCallback(() => stopVoice(), []);
  const play = useCallback((id: string) => {
    const c = cardsRef.current.find((x) => x.id === id);
    if (c?.speak) playVoice(id, c.speak);
  }, []);
  const speakingId = usePlayingKey();
  const setVoice = useCallback(() => {}, []);

  /* ---- cards ---- */
  const addCard = useCallback(
    (n: HeraldSend, seed: boolean): string => {
      const cur = cardsRef.current;
      const ex = cur.find((c) => c.app === n.app);
      const cardId = ex?.id ?? `hc${++seq.current}`;
      const item = { id: `${cardId}-${++seq.current}`, title: n.title, body: n.body ?? "" };
      if (ex) {
        setCards(
          cur.map((c) =>
            c === ex
              ? {
                  ...c,
                  items: [item, ...c.items],
                  icon: n.icon ?? c.icon,
                  buttons: n.buttons ?? c.buttons,
                  confirm: n.confirm ?? c.confirm,
                  reply: n.reply ?? c.reply,
                  snooze: n.snooze ?? c.snooze,
                  speak: n.speak ? sampleName(n.speak) : c.speak,
                }
              : c,
          ),
        );
      } else {
        const card: HeraldCardModel = {
          id: cardId,
          app: n.app,
          appName: n.appName ?? n.app,
          icon: n.icon ?? "herald",
          items: [item],
          buttons: n.buttons ?? [],
          confirm: n.confirm,
          reply: n.reply,
          snooze: n.snooze,
          speak: n.speak ? sampleName(n.speak) : undefined,
          seedIndex: seed ? seeds.current++ : undefined,
        };
        setCards(seed ? [...cur, card] : [card, ...cur]);
      }
      if (!seed && !dockedRef.current) expandFor(6000);
      return cardId;
    },
    [expandFor, setCards],
  );

  const place = useCallback(
    (n: HeraldSend, seed: boolean): string => {
      if (!seed) setRing((r) => r + 1);
      const q = quietRef.current;
      if (q.hold && inWindow(nowMinute(), q.from, q.to)) {
        const id = `hh${++seq.current}`;
        setHeld([...heldRef.current, { ...n, id }]);
        return id;
      }
      return addCard(n, seed);
    },
    [addCard, nowMinute, setHeld],
  );
  const send = useCallback((n: HeraldSend) => place(n, false), [place]);
  const seed = useCallback((n: HeraldSend) => place(n, true), [place]);

  const showHeld = useCallback(() => {
    const list = heldRef.current;
    setHeld([]);
    list.forEach((h) => addCard(h, false));
    if (list.length && dockedRef.current === false) expandFor(6000);
  }, [addCard, expandFor, setHeld]);

  const quietKey = `${quiet.hold}|${quiet.from}|${quiet.to}|${quiet.pretendNow}`;
  useEffect(() => {
    const q = quietRef.current;
    if (heldRef.current.length === 0) return;
    if (q.hold && inWindow(nowMinute(), q.from, q.to)) return;
    const list = heldRef.current;
    heldRef.current = [];
    queueMicrotask(() => {
      setHeldState([]);
      list.forEach((h) => addCard(h, false));
    });
  }, [quietKey, nowMinute, addCard]);

  const closeCard = useCallback(
    (id: string) => {
      const c = cardsRef.current.find((x) => x.id === id);
      if (!c) return;
      setHistory((h) => h + c.items.length);
      setCards(cardsRef.current.filter((x) => x.id !== id));
      setSnoozingIds((s) => s.filter((x) => x !== id));
    },
    [setCards],
  );
  const dismissItem = useCallback(
    (cardId: string, itemId: string) => {
      const c = cardsRef.current.find((x) => x.id === cardId);
      if (!c) return;
      if (c.items.length <= 1) return closeCard(cardId);
      setHistory((h) => h + 1);
      setCards(cardsRef.current.map((x) => (x === c ? { ...x, items: x.items.filter((i) => i.id !== itemId) } : x)));
    },
    [closeCard, setCards],
  );
  const dismissAll = useCallback(() => {
    const total = cardsRef.current.reduce((s, c) => s + c.items.length, 0);
    setHistory((h) => h + total);
    setCards([]);
    setSnoozingIds([]);
    setExpanded(false);
  }, [setCards, setExpanded]);
  const setSnoozing = useCallback((id: string, on: boolean) => {
    setSnoozingIds((s) => (on ? (s.includes(id) ? s : [...s, id]) : s.filter((x) => x !== id)));
  }, []);

  const setQuiet = useCallback((patch: Partial<HeraldQuiet>) => {
    const next = { ...quietRef.current, ...patch };
    quietRef.current = next;
    setQuietState(next);
  }, []);

  const value = useMemo<HeraldInternals>(() => {
    const live = cards.filter((c) => !snoozingIds.includes(c.id));
    return {
      onScreen: live.length,
      pending: live.reduce((s, c) => s + c.items.length, 0),
      history,
      snoozed: cards.length - live.length,
      held: held.length,
      voice: true,
      speaking: speakingId !== null,
      quiet,
      docked,
      send,
      dismissAll,
      show,
      setVoice,
      setQuiet,
      isQuiet,
      nowMinute,
      ring,
      cards,
      expanded,
      speakingId,
      snoozingIds,
      heldUntil: hhmm(quiet.to),
      seed,
      playVoice: play,
      stopVoice: stop,
      closeCard,
      dismissItem,
      setSnoozing,
      showHeld,
      compact,
      toggle,
      setDocked,
      setHold,
    };
  }, [cards, held, history, snoozingIds, speakingId, quiet, docked, expanded, ring, send, dismissAll, show, setVoice, setQuiet, isQuiet, nowMinute, seed, play, stop, closeCard, dismissItem, setSnoozing, showHeld, compact, toggle, setDocked, setHold]);

  return (
    <HeraldContext.Provider value={value}>
      <HeraldInternalContext.Provider value={value}>{children}</HeraldInternalContext.Provider>
    </HeraldContext.Provider>
  );
}

export default HeraldHost;

/** The cards, used identically in the hero dock and in the fixed overlay. */
export function HeraldCards({ cards, stagger = false }: { cards: HeraldCardModel[]; stagger?: boolean }) {
  const h = useHeraldInternal();
  return (
    <AnimatePresence initial>
      {cards.map((c) => (
        <LiveBanner
          key={c.id}
          app={c.appName}
          icon={c.icon}
          items={c.items}
          buttons={c.buttons}
          confirmText={c.confirm}
          reply={c.reply}
          snoozeSeconds={c.snooze?.seconds}
          snoozeLabel={c.snooze?.label}
          speaking={h.speakingId === c.id}
          onToggleVoice={c.speak ? () => (h.speakingId === c.id ? h.stopVoice() : h.playVoice(c.id)) : undefined}
          delay={stagger && c.seedIndex !== undefined ? c.seedIndex * 0.14 : 0}
          onClose={() => h.closeCard(c.id)}
          onDismissItem={(itemId) => h.dismissItem(c.id, itemId)}
          onSnoozeChange={(on) => h.setSnoozing(c.id, on)}
        />
      ))}
    </AnimatePresence>
  );
}

/** Header above a stack: counts and (in the overlay) Dismiss all plus the snoozed/held lines. */
export function StackHeader({ full = false }: { full?: boolean }) {
  const h = useHeraldInternal();
  const plural = (n: number, w: string) => `${n} ${w}${n === 1 ? "" : "s"}`;
  const extra = h.snoozed > 0 ? `${h.snoozed} snoozed` : "";
  return (
    <>
      <div className="hb-head">
        <span className="mono hb-head-l">
          {h.onScreen === h.pending ? plural(h.pending, "banner") : `${plural(h.onScreen, "banner")} · ${h.pending} new`}
        </span>
        <span className="flex shrink-0 items-center gap-1.5">
          {full && h.cards.length > 0 && (
            <button type="button" className="hb-voice" onClick={h.dismissAll}>Dismiss all</button>
          )}
        </span>
      </div>
      {full && (extra || h.held > 0) && (
        <p className="hb-heldline" role="status">
          {extra}
          {extra && h.held > 0 && " · "}
          {h.held > 0 && `${h.held} held until ${h.heldUntil}`}
          {h.held > 0 && (
            <button type="button" className="hb-pill-btn" onClick={h.showHeld}>Show anyway</button>
          )}
        </p>
      )}
    </>
  );
}
