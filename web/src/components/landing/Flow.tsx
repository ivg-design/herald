"use client";
import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { Send } from "lucide-react";
import s from "./flow.module.css";
import MiniIcon from "./MiniIcon";
import { useHerald } from "@/components/herald/useHerald";
import type { HeraldButton } from "@/components/herald/types";
import { EASE } from "@/lib/config";

type Key = "title" | "status" | "body" | "log" | "deploy";
const FIELDS: { k: Key; json: string; label: string }[] = [
  { k: "title", json: "Build passed", label: "title" },
  { k: "status", json: "OK", label: "status" },
  { k: "body", json: "142 tests, 0 failures · main", label: "body" },
  { k: "log", json: "https://ci.example.com/142", label: "log" },
  { k: "deploy", json: "deploy", label: "action" },
];
/** Which row each field's cell sits in, and which cells share it. */
const ROWS: Key[][] = [["title", "status"], ["body"], ["log", "deploy"]];
const ROW_PX = [56, 44, 44];

const STEPS = [
  { n: 1, name: "Manifest", text: "The app declares the fields it can send. Press “empty” on a field to send it blank, as if the app had nothing to say there." },
  { n: 2, name: "Template", text: "Your template places each field in a cell of the grid. When a field is empty its cell holds nothing; a row collapses only when every cell in it is empty." },
  { n: 3, name: "Banner", text: "Herald renders the same values through the same grid. Switch the rule to “keep space” to see what collapse-empty saves." },
];

export default function Flow() {
  const reduce = useReducedMotion();
  const herald = useHerald();
  const [step, setStep] = useState(3);
  const [sent, setSent] = useState<{ sig: string; msg: string } | null>(null);
  const [empty, setEmpty] = useState<Set<Key>>(new Set());
  const [collapse, setCollapse] = useState(true);
  const [hot, setHot] = useState<Key | null>(null);
  const toggle = (k: Key) =>
    setEmpty((s) => {
      const n = new Set(s);
      if (n.has(k)) n.delete(k);
      else n.add(k);
      return n;
    });
  const isEmpty = (k: Key) => empty.has(k);
  const rowGone = (i: number) => collapse && ROWS[i].every(isEmpty);
  const collapsedRows = ROWS.map((r, i) => (rowGone(i) ? i + 1 : 0)).filter(Boolean);
  const summary = empty.size === 0
    ? "Nothing is empty: all three rows are drawn."
    : collapsedRows.length
      ? `Row ${collapsedRows.join(" and ")} collapsed: every cell in it is empty.`
      : collapse
        ? "Cells are empty, but each row still has a filled cell, so no row collapses."
        : "Empty cells keep their place; the banner stays full height.";

  const sig = `${[...empty].sort().join(",")}|${collapse}`;
  const sendTest = () => {
    const buttons: HeraldButton[] = [];
    if (!isEmpty("log")) buttons.push({ label: "Open log", role: "open", primary: true, url: "ci.example.com/142" });
    if (!isEmpty("deploy")) buttons.push({ label: "Deploy", role: "deploy" });
    herald.send({
      app: "ci.bot",
      appName: "CI Bot",
      icon: "ci",
      title: isEmpty("title") ? "" : "Build passed",
      body: isEmpty("body") ? undefined : "142 tests, 0 failures · main",
      buttons,
      confirm: "Deploy to production?",
    });
    const drawn = 3 - collapsedRows.length;
    const names = collapsedRows.map((r) => ["header", "body", "buttons"][r - 1]);
    const tail = names.length ? `, ${names.join(" and ")} collapsed` : collapse || empty.size === 0 ? "" : ", empty cells keep their place";
    setSent({ sig, msg: `Sent through the template: ${drawn} row${drawn === 1 ? "" : "s"}${tail}` });
  };

  const hh = (k: Key) => ({
    "data-k": k,
    "data-hot": String(hot === k),
    tabIndex: 0,
    onMouseEnter: () => setHot(k),
    onMouseLeave: () => setHot((h) => (h === k ? null : h)),
    onFocus: () => setHot(k),
    onBlur: () => setHot((h) => (h === k ? null : h)),
  });
  const marker = (n: number, label: string) => (
    <button type="button" aria-hidden tabIndex={-1} onClick={() => setStep(n)} className={s.marker}>
      <b>{String(n).padStart(2, "0")}</b> {label}
    </button>
  );

  return (
    <section id="flow" className="section section-dark">
      <div className="shell">
        <p className="eyebrow md:text-center">How it fits together</p>
        <h2 className="display text-[clamp(40px,6vw,72px)]" style={{ lineHeight: 1 }}>
          <span className="block">Apps declare.</span>
          <span className="block pl-[8vw] md:pl-[20%]">You design.</span>
          <span className="block pl-[16vw] md:pl-[38%]">Herald renders.</span>
        </h2>
        <p className="lede mx-auto mt-8 md:max-w-[56ch] md:text-center" style={{ maxWidth: "62ch" }}>
          An app registers a manifest once: the fields it can send, sample values, the actions it offers. You lay those fields out in the Designer. Every notification from then on is rendered through your template.
        </p>

        <div className="mt-12 flex flex-wrap items-center justify-between gap-4">
          <div role="tablist" aria-label="Walkthrough step" className="inline-flex rounded-lg border border-line p-0.5">
            {STEPS.map((s) => (
              <button
                key={s.n}
                role="tab"
                type="button"
                aria-selected={step === s.n}
                onClick={() => setStep(s.n)}
                className="h-10 cursor-pointer rounded-md px-4 text-[14px] font-medium transition-colors duration-150"
                style={{ background: step === s.n ? "var(--accent)" : "transparent", color: step === s.n ? "var(--accent-ink)" : "var(--muted)" }}
              >
                {s.n} · {s.name}
              </button>
            ))}
          </div>
          <div role="group" aria-label="When a field is empty" className="inline-flex items-center gap-2 text-[13px] text-muted">
            When a field is empty:
            <span className="inline-flex rounded-lg border border-line p-0.5">
              {[true, false].map((v) => (
                <button
                  key={String(v)}
                  type="button"
                  aria-pressed={collapse === v}
                  onClick={() => setCollapse(v)}
                  className="h-9 cursor-pointer rounded-md px-3 text-[13px] font-medium"
                  style={{ background: collapse === v ? "var(--surface-2)" : "transparent", color: collapse === v ? "var(--ink)" : "var(--muted)" }}
                >
                  {v ? "collapse" : "keep space"}
                </button>
              ))}
            </span>
          </div>
        </div>
        <p className="mt-4 mb-0 max-w-[78ch] text-[14.5px] leading-relaxed text-muted" aria-live="polite">{STEPS[step - 1].text}</p>

        <div className={`${s.pipe} mt-10`} data-hot={String(hot !== null)}>
          {/* 01 manifest */}
          <article className={s.col} data-on={step === 1}>
            {marker(1, "manifest")}
            <div className={s.json}>
              <div className="text-muted">{"{ \"app\": \"ci.bot\","}</div>
              {FIELDS.map((f, i) => {
                const e = isEmpty(f.k);
                return (
                  <div key={f.k} className={s.jline} {...hh(f.k)}>
                    <span className={s.jtext}>
                      <span className={s.jkey}>&quot;{f.label}&quot;</span>
                      <span className="text-muted">: </span>
                      <span style={{ color: e ? "var(--signal)" : "var(--ink)" }}>&quot;{e ? "" : f.json}&quot;</span>
                      {i < FIELDS.length - 1 ? "," : ""}
                    </span>
                    <button
                      type="button"
                      aria-pressed={e}
                      aria-label={`Send ${f.label} empty`}
                      onClick={() => toggle(f.k)}
                      className="shrink-0 cursor-pointer rounded px-2 text-[11px] font-sans font-semibold"
                      style={{ height: 24, background: e ? "var(--signal)" : "var(--surface-2)", color: e ? "#fff5f2" : "var(--muted)" }}
                    >
                      {e ? "empty" : "empty?"}
                    </button>
                  </div>
                );
              })}
              <div className="text-muted">{"}"}</div>
            </div>
          </article>

          {/* 02 template */}
          <article className={`${s.col} mt-0`} data-on={step === 2}>
            {marker(2, "template · 4 × 3 grid")}
            <div className={s.canvas}>
              <div
                className="grid gap-2"
                style={{
                  gridTemplateColumns: "repeat(4, minmax(0, 1fr))",
                  gridTemplateRows: ROW_PX.map((h, i) => `${rowGone(i) ? 6 : h}px`).join(" "),
                  transition: reduce ? "none" : "grid-template-rows 350ms var(--ease-quint)",
                }}
              >
                <div className={s.gcell} data-rail="true" style={{ gridArea: "1 / 1 / 4 / 2" }}>icon</div>
                <Cell hh={hh("title")} area="1 / 2 / 2 / 4" name="title" empty={isEmpty("title")} collapse={collapse} />
                <Cell hh={hh("status")} area="1 / 4 / 2 / 5" name="status" empty={isEmpty("status")} collapse={collapse} />
                <Cell hh={hh("body")} area="2 / 2 / 3 / 5" name="body" empty={isEmpty("body")} collapse={collapse} gone={rowGone(1)} />
                <Cell hh={hh("log")} area="3 / 2 / 4 / 4" name="log" empty={isEmpty("log")} collapse={collapse} gone={rowGone(2)} />
                <Cell hh={hh("deploy")} area="3 / 4 / 4 / 5" name="action" empty={isEmpty("deploy")} collapse={collapse} gone={rowGone(2)} />
              </div>
            </div>
          </article>

          {/* 03 banner */}
          <article className={s.col} data-on={step === 3}>
            {marker(3, "banner")}
            <div className="mb p-3" style={{ borderRadius: 10 }}>
              <div className="flex items-start gap-3">
                <MiniIcon size={28} />
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2.5" style={{ minHeight: 32 }}>
                    <span className={`${s.bel} min-w-0 flex-1 truncate text-[14px] font-medium`} {...hh("title")}>{isEmpty("title") ? (collapse ? "" : <Hold w={110} />) : "Build passed"}</span>
                    {!isEmpty("status") ? <span className={`${s.bel} rounded-full px-2 py-px text-[10px] font-bold`} {...hh("status")} style={{ background: "#2fbf71", color: "#0f1317" }}>OK</span> : !collapse && <Hold w={28} />}
                  </div>
                  <Row show={!rowGone(1)}>{isEmpty("body") ? <Hold w={180} h={16} /> : <p className={`${s.bel} m-0 mt-2 text-[12px] text-muted`} {...hh("body")}>142 tests, 0 failures · main</p>}</Row>
                  <Row show={!rowGone(2)}>
                    <div className="flex flex-wrap gap-2 pt-2.5">
                      {isEmpty("log") ? <Hold w={74} h={32} /> : <span className={`mb-btn is-primary ${s.bel}`} {...hh("log")} style={{ height: 32 }}>Open log</span>}
                      {isEmpty("deploy") ? <Hold w={68} h={32} /> : <span className={`mb-btn ${s.bel}`} {...hh("deploy")} style={{ height: 32 }}>Deploy</span>}
                    </div>
                  </Row>
                </div>
              </div>
            </div>
            <div className="mt-4 flex flex-wrap items-center gap-3">
              <button type="button" onClick={sendTest} className="btn btn-ghost btn-sm cursor-pointer gap-2">
                <Send aria-hidden className="size-3.5" /> Send test
              </button>
            </div>
          </article>
        </div>
        <p className="mt-4 mb-0 text-[13.5px] text-muted" role="status" aria-live="polite">{summary}</p>
        <p className="mono mt-2 mb-0 min-h-[1.5em] text-[12.5px]" style={{ color: "var(--accent)" }} role="status" aria-live="polite" aria-label="Send test outcome">{sent && sent.sig === sig ? sent.msg : ""}</p>
      </div>
    </section>
  );
}

function Row({ show, children }: { show: boolean; children: React.ReactNode }) {
  const reduce = useReducedMotion();
  return (
    <AnimatePresence initial={false}>
      {show && (
        <motion.div
          initial={reduce ? false : { height: 0, opacity: 0 }}
          animate={{ height: "auto", opacity: 1 }}
          exit={{ height: 0, opacity: 0 }}
          transition={{ duration: reduce ? 0 : 0.35, ease: EASE.quint }}
          style={{ overflow: "hidden" }}
        >
          {children}
        </motion.div>
      )}
    </AnimatePresence>
  );
}

/** A reserved, empty cell (keep-space mode). */
function Hold({ w, h = 20 }: { w: number; h?: number }) {
  return <span aria-hidden className={s.hold} style={{ width: w, height: h }} />;
}

function Cell({ area, name, empty, collapse, gone, hh }: { area: string; name: string; empty?: boolean; collapse?: boolean; gone?: boolean; hh: Record<string, unknown> }) {
  const isEmpty = !!empty;
  return (
    <div className={s.gcell} {...hh} data-empty={isEmpty} style={{ gridArea: area, opacity: gone ? 0 : 1 }}>
      {gone ? "" : (<>{name}{isEmpty && !collapse && <span className={s.held}>held</span>}</>)}
    </div>
  );
}
