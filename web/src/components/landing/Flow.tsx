"use client";
import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { Send } from "lucide-react";
import s from "./flow.module.css";
import MiniIcon from "./MiniIcon";
import SectionHead from "./SectionHead";
import { useHerald } from "@/components/herald/useHerald";
import type { HeraldButton } from "@/components/herald/types";
import type { Transition } from "framer-motion";
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
const ROW_PX = [56, 52, 52];
const GAP = 8;

export default function Flow() {
  const reduce = useReducedMotion();
  const herald = useHerald();
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
  const vis = [0, 1, 2].map((i) => !rowGone(i));
  const g1 = vis[0] && vis[1] ? GAP : 0;
  const g2 = vis[2] && (vis[0] || vis[1]) ? GAP : 0;
  const trackRows = [vis[0] ? ROW_PX[0] : 0, g1, vis[1] ? ROW_PX[1] : 0, g2, vis[2] ? ROW_PX[2] : 0].map((n) => `${n}px`).join(" ");
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
  const dur = reduce ? 0 : 0.56;
  const layoutT: Transition = { duration: dur, ease: EASE.expo };

  return (
    <section id="flow" className="section">
      <div className="shell">
        <div className="g">
          <SectionHead
            title="Apps declare. You design. Herald renders."
            titleCols="lg:col-span-9"
            ledeCols="lg:col-span-7"
            lede="An app registers a manifest once: the fields it can send, sample values, the actions it offers. You lay those fields out in the Designer. Every notification from then on is rendered through your template."
          />

          {/* manifest */}
          <article className="col-span-full min-w-0 lg:col-span-4 lg:col-start-1">
            <h3 className={s.head}>manifest</h3>
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
                    <button type="button" aria-pressed={e} aria-label={`Send ${f.label} empty`} onClick={() => toggle(f.k)} className={s.empty}>
                      {e ? "empty" : "empty?"}
                    </button>
                  </div>
                );
              })}
              <div className="text-muted">{"}"}</div>
            </div>
          </article>

          {/* template */}
          <article className="col-span-full min-w-0 lg:col-span-4">
            <h3 className={s.head}>template · 4 × 3</h3>
            <div
              className={s.tgrid}
              style={{ gridTemplateRows: trackRows, transition: reduce ? "none" : undefined }}
            >
              <div className={`cell ${s.gcell} ${s.icell}`} style={{ gridArea: "1 / 1 / 6 / 2" }}><span className="slot">icon</span><MiniIcon size={32} /></div>
              <Cell hh={hh("title")} area="1 / 2 / 2 / 4" name="title" empty={isEmpty("title")} />
              <Cell hh={hh("status")} area="1 / 4 / 2 / 5" name="status" empty={isEmpty("status")} />
              <Cell hh={hh("body")} area="3 / 2 / 4 / 5" name="body" empty={isEmpty("body")} gone={rowGone(1)} />
              <Cell hh={hh("log")} area="5 / 2 / 6 / 4" name="log" empty={isEmpty("log")} gone={rowGone(2)} />
              <Cell hh={hh("deploy")} area="5 / 4 / 6 / 5" name="action" empty={isEmpty("deploy")} gone={rowGone(2)} />
            </div>
            <div role="group" aria-label="When a field is empty" className={s.sw}>
              <span>when a field is empty:</span>
              <span className="inline-flex rounded-md border border-line p-0.5">
                {[true, false].map((v) => (
                  <button
                    key={String(v)}
                    type="button"
                    aria-pressed={collapse === v}
                    onClick={() => setCollapse(v)}
                    className="h-7 cursor-pointer rounded px-2.5 text-[12px] font-medium"
                    style={{ background: collapse === v ? "var(--surface-2)" : "transparent", color: collapse === v ? "var(--ink)" : "var(--muted)", transition: "background-color var(--t-state) var(--ease-quint)" }}
                  >
                    {v ? "collapse" : "keep space"}
                  </button>
                ))}
              </span>
            </div>
            <p className="readout m-0 mt-3" role="status" aria-live="polite">{summary}</p>
          </article>

          {/* banner */}
          <article className="col-span-full min-w-0 lg:col-span-4">
            <h3 className={s.head}>banner</h3>
            <motion.div layout transition={layoutT} className="mb p-3" style={{ borderRadius: 14 }}>
              <div className="flex items-start gap-3">
                <MiniIcon size={28} />
                <div className="min-w-0 flex-1">
                  <motion.div layout transition={layoutT} className="flex items-center gap-2.5" style={{ minHeight: 32 }}>
                    <span className={`${s.bel} min-w-0 flex-1 truncate text-[15px] font-semibold`} {...hh("title")}>{isEmpty("title") ? (collapse ? "" : <Hold w={110} />) : "Build passed"}</span>
                    {!isEmpty("status") ? <span className={`${s.bel} rounded-full px-2 py-px text-[10px] font-bold`} {...hh("status")} style={{ background: "var(--blue)", color: "#fff" }}>OK</span> : !collapse && <Hold w={28} />}
                  </motion.div>
                  <Row show={!rowGone(1)} t={layoutT}>{isEmpty("body") ? <Hold w={180} h={16} /> : <p className={`${s.bel} m-0 mt-2 text-[13px]`} {...hh("body")} style={{ color: "var(--mb-muted)" }}>142 tests, 0 failures · main</p>}</Row>
                  <Row show={!rowGone(2)} t={layoutT}>
                    <div className="flex flex-wrap gap-2 pt-2.5">
                      {isEmpty("log") ? <Hold w={74} h={32} /> : <span className={`mb-btn is-primary ${s.bel}`} {...hh("log")} style={{ height: 32 }}>Open log</span>}
                      {isEmpty("deploy") ? <Hold w={68} h={32} /> : <span className={`mb-btn ${s.bel}`} {...hh("deploy")} style={{ height: 32 }}>Deploy</span>}
                    </div>
                  </Row>
                </div>
              </div>
            </motion.div>
            <div className="mt-4">
              <button type="button" onClick={sendTest} className="btn btn-ghost btn-sm cursor-pointer gap-2">
                <Send aria-hidden className="size-3.5" /> Send test
              </button>
            </div>
          </article>

          <p className="readout col-span-full m-0 min-h-[1.5em]" style={{ color: "var(--accent-text)" }} role="status" aria-live="polite" aria-label="Send test outcome">{sent && sent.sig === sig ? sent.msg : ""}</p>
        </div>
      </div>
    </section>
  );
}

function Row({ show, t, children }: { show: boolean; t: Transition; children: React.ReactNode }) {
  return (
    <AnimatePresence initial={false}>
      {show && (
        <motion.div
          layout
          initial={{ height: 0 }}
          animate={{ height: "auto" }}
          exit={{ height: 0 }}
          transition={t}
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

function Cell({ area, name, empty, gone, hh }: { area: string; name: string; empty?: boolean; gone?: boolean; hh: Record<string, unknown> }) {
  return (
    <div className={`cell ${s.gcell}`} {...hh} data-empty={!!empty} data-gone={!!gone} style={{ gridArea: area }}>
      <span className="slot">{name}</span>
      <span className={s.tok}>{`{${name}}`}</span>
    </div>
  );
}
