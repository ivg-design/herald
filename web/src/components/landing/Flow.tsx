"use client";
import { useState } from "react";
import { AnimatePresence, motion, useReducedMotion } from "framer-motion";
import { Send } from "lucide-react";
import s from "./flow.module.css";
import MiniIcon from "./MiniIcon";
import SectionHead from "./SectionHead";
import { useHerald } from "@/components/herald/useHerald";
import type { HeraldButton, HeraldIcon, HeraldRole } from "@/components/herald/types";
import type { Transition } from "framer-motion";
import { EASE } from "@/lib/config";

type Key = "title" | "status" | "body" | "log" | "deploy";
type Opt = "status" | "body" | "deploy";
const FIELDS: { k: Key; label: string }[] = [
  { k: "title", label: "title" },
  { k: "status", label: "status" },
  { k: "body", label: "body" },
  { k: "log", label: "log" },
  { k: "deploy", label: "action" },
];
/** Which row each field's cell sits in, and which cells share it. */
const ROWS: Key[][] = [["title", "status"], ["body"], ["log", "deploy"]];
const ROW_PX = [56, 52, 52];
const GAP = 8;
/** The template's own line limit for {body} (text.maxLines). A long value wraps and stops here. */
const BODY_LINES = 5;

const LONG_PASS = "All 142 tests passed on main in 3m 12s. Coverage 91.4 percent, no new warnings, artifacts published to the release bucket and the changelog updated for the next tag.";
const LONG_FAIL = "FAILED in tests/api/orders.test.ts: expected status 200 but received 502 from the payments service after 3 retries. The remaining 41 tests were skipped. Last log line: connect ETIMEDOUT 10.0.4.17:443 while reaching the payments gateway.";

interface Act { label: string; id: string; role: HeraldRole }
interface Preset {
  id: string;
  name: string;
  app: string;
  appName: string;
  icon: HeraldIcon;
  title: string;
  /** Values the sender can put in `status`; none means the field is not in this sender's manifest. */
  status: string[];
  /** [short, long]. */
  body: string[];
  bodyStart: number;
  log?: { url: string; label: string };
  actions: Act[];
  reply?: string;
}
const SNOOZE: Act = { label: "Snooze", id: "snooze", role: "snooze" };
const DISMISS: Act = { label: "Dismiss", id: "dismiss", role: "dismiss" };
const PRESETS: Preset[] = [
  {
    id: "pass", name: "ci.bot passed", app: "ci.bot", appName: "CI Bot", icon: "ci", title: "Build passed",
    status: ["OK", "RUNNING"], body: ["142 tests, 0 failures · main", LONG_PASS], bodyStart: 0,
    log: { url: "https://ci.example.com/142", label: "Open log" },
    actions: [{ label: "Deploy", id: "deploy", role: "deploy" }, SNOOZE],
  },
  {
    id: "fail", name: "ci.bot failed", app: "ci.bot", appName: "CI Bot", icon: "ci", title: "Build failed",
    status: ["FAILED", "RUNNING"], body: ["3 failures · main", LONG_FAIL], bodyStart: 1,
    log: { url: "https://ci.example.com/143", label: "Open log" },
    actions: [SNOOZE, DISMISS],
  },
  {
    id: "web", name: "WebWatcher", app: "webwatcher.page", appName: "WebWatcher", icon: "web", title: "Price changed",
    status: [], body: ["$129 → $109 · Rive Marketplace", "Was $129, now $109. The same page also changed its shipping note from “5 days” to “2 days”."], bodyStart: 0,
    log: { url: "https://market.example.com/pack", label: "Open" },
    actions: [SNOOZE, DISMISS],
  },
  {
    id: "agent", name: "Claude", app: "claude.agent", appName: "Claude", icon: "claude", title: "Deploy to staging now?",
    status: [], body: ["Tests pass on feature/login.", "Tests pass on feature/login, but the review is still open. I can deploy to staging now, or wait for the review and deploy after it."], bodyStart: 0,
    actions: [{ label: "Reply", id: "reply", role: "dismiss" }, DISMISS],
    reply: "Deploy it, then tell me when the checks are green.",
  },
];
type OptState = Record<Opt, number>;
const startOpts = (p: Preset): OptState => ({ status: 0, body: p.bodyStart, deploy: 0 });
const OPT_NAME: Record<Opt, string> = { status: "Status", body: "Body", deploy: "Action" };
const BODY_NAMES = ["short", "long"];

export default function Flow() {
  const reduce = useReducedMotion();
  const herald = useHerald();
  const [pi, setPi] = useState(0);
  const P = PRESETS[pi];
  const [opts, setOpts] = useState<OptState>(startOpts(PRESETS[0]));
  const [sent, setSent] = useState<{ sig: string; msg: string } | null>(null);
  const [override, setOverride] = useState<Set<Key>>(new Set());
  const [collapse, setCollapse] = useState(true);
  const [hot, setHot] = useState<Key | null>(null);

  const optLen = (o: Opt) => (o === "status" ? P.status.length : o === "body" ? P.body.length : P.actions.length);
  const optList = (o: Opt): string[] => (o === "status" ? P.status : o === "body" ? BODY_NAMES : P.actions.map((a) => a.label));
  /** What the sender puts in the field right now ("" = nothing). */
  const raw = (k: Key): string => {
    switch (k) {
      case "title": return P.title;
      case "status": return P.status[opts.status] ?? "";
      case "body": return P.body[opts.body] ?? "";
      case "log": return P.log?.url ?? "";
      case "deploy": return P.actions[opts.deploy]?.id ?? "";
    }
  };
  const notSent = (k: Key) => (k === "log" ? !P.log : k === "status" ? P.status.length === 0 : false);
  const isEmpty = (k: Key) => override.has(k) || raw(k) === "";
  const val = (k: Key) => (isEmpty(k) ? "" : raw(k));
  const toggle = (k: Key) => {
    if (notSent(k)) return;
    const cur = isEmpty(k);
    setOverride((o) => {
      const n = new Set(o);
      if (cur) n.delete(k);
      else n.add(k);
      return n;
    });
    if (cur && (k === "status" || k === "body" || k === "deploy") && opts[k] >= optLen(k)) setOpts((o) => ({ ...o, [k]: 0 }));
  };
  const cycle = (o: Opt) => {
    setOpts((p) => ({ ...p, [o]: (p[o] + 1) % (optLen(o) + 1) }));
    setOverride((x) => {
      const n = new Set(x);
      n.delete(o);
      return n;
    });
  };
  const pick = (i: number) => {
    setPi(i);
    setOpts(startOpts(PRESETS[i]));
    setSent(null);
  };

  const rowGone = (i: number) => collapse && ROWS[i].every(isEmpty);
  const vis = [0, 1, 2].map((i) => !rowGone(i));
  const g1 = vis[0] && vis[1] ? GAP : 0;
  const g2 = vis[2] && (vis[0] || vis[1]) ? GAP : 0;
  const trackRows = [vis[0] ? ROW_PX[0] : 0, g1, vis[1] ? ROW_PX[1] : 0, g2, vis[2] ? ROW_PX[2] : 0].map((n) => `${n}px`).join(" ");
  const collapsedRows = ROWS.map((r, i) => (rowGone(i) ? i + 1 : 0)).filter(Boolean);
  const emptyCount = FIELDS.filter((f) => isEmpty(f.k)).length;
  const longBody = !isEmpty("body") && opts.body === 1;
  const limitNote = longBody && !rowGone(1) ? ` A long body stops at ${BODY_LINES} lines.` : "";
  const summary = (emptyCount === 0
    ? "Nothing is empty: all three rows are drawn."
    : collapsedRows.length
      ? `Row ${collapsedRows.join(" and ")} collapsed: every cell in it is empty.`
      : collapse
        ? "Cells are empty, but each row still has a filled cell, so no row collapses."
        : "Empty cells keep their place; the banner stays full height.") + limitNote;

  const sig = `${pi}|${FIELDS.map((f) => val(f.k)).join("¦")}|${collapse}`;
  const act = isEmpty("deploy") ? null : P.actions[opts.deploy];
  const sendTest = () => {
    const buttons: HeraldButton[] = [];
    if (P.log && !isEmpty("log")) buttons.push({ label: P.log.label, role: "open", primary: true, url: P.log.url.replace(/^https?:\/\//, "") });
    if (act && act.id !== "reply") buttons.push({ label: act.label, role: act.role });
    herald.send({
      app: P.app,
      appName: P.appName,
      icon: P.icon,
      title: val("title"),
      body: isEmpty("body") ? undefined : val("body"),
      buttons,
      confirm: act?.role === "deploy" ? "Deploy to production?" : undefined,
      reply: act?.id === "reply" && P.reply ? { transcript: P.reply } : undefined,
    });
    const drawn = 3 - collapsedRows.length;
    const names = collapsedRows.map((r) => ["header", "body", "buttons"][r - 1]);
    const tail = names.length ? `, ${names.join(" and ")} collapsed` : collapse || emptyCount === 0 ? "" : ", empty cells keep their place";
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

  const chip = (o: Opt, k: Key) => {
    if (notSent(k)) return <span className={s.optslot}><span className={s.nosent}>not sent</span></span>;
    const names = [...optList(o), "none"];
    const cur = override.has(k) ? "none" : names[opts[o]];
    return (
      <button type="button" className={s.opt} aria-label={`${OPT_NAME[o]} value: ${cur}. Press for the next`} onClick={() => cycle(o)}>
        {cur}
      </button>
    );
  };

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
            <div role="group" aria-label="Payload" className={s.presets}>
              {PRESETS.map((p, i) => (
                <button key={p.id} type="button" aria-pressed={pi === i} onClick={() => pick(i)} className={s.preset}>
                  {p.name}
                </button>
              ))}
            </div>
            <div className={s.json}>
              <div className={`${s.jhead} text-muted`}>{`{ "app": "${P.app}",`}</div>
              {FIELDS.map((f, i) => {
                const e = isEmpty(f.k);
                const ns = notSent(f.k);
                const o: Opt | null = f.k === "status" || f.k === "body" || f.k === "deploy" ? f.k : null;
                const shown = ns || e ? "" : raw(f.k);
                return (
                  <div key={f.k} className={s.jline} {...hh(f.k)}>
                    <span className={s.jtext} title={shown || undefined}>
                      <span className={s.jkey}>&quot;{f.label}&quot;</span>
                      <span className="text-muted">: </span>
                      {ns ? <span className="text-muted">not in this manifest</span> : <span style={{ color: e ? "var(--signal)" : "var(--ink)" }}>&quot;{shown}&quot;</span>}
                      {!ns && i < FIELDS.length - 1 ? "," : ""}
                    </span>
                    {o ? chip(o, f.k) : <span className={s.optslot} aria-hidden />}
                    <button type="button" aria-pressed={e} aria-label={`Send ${f.label} empty`} disabled={ns} onClick={() => toggle(f.k)} className={s.empty}>
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
            <div className={s.tbox}>
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
            <p className={`readout ${s.sline}`} role="status" aria-live="polite">{summary}</p>
          </article>

          {/* banner */}
          <article className="col-span-full min-w-0 lg:col-span-4">
            <h3 className={s.head}>banner</h3>
            <div className={s.stage}>
              <motion.div layout transition={layoutT} className="mb p-3" style={{ borderRadius: 14 }}>
                <div className="flex items-start gap-3">
                  <MiniIcon size={28} />
                  <div className="min-w-0 flex-1">
                    <motion.div layout transition={layoutT} className="flex items-center gap-2.5" style={{ minHeight: 32 }}>
                      <span className={`${s.bel} ${s.btitle} min-w-0 flex-1`} {...hh("title")}>{isEmpty("title") ? (collapse ? "" : <Hold w={110} />) : <span className={s.clamp2}>{P.title}</span>}</span>
                      {!isEmpty("status") ? <span className={`${s.bel} rounded-full px-2 py-px text-[10px] font-bold`} {...hh("status")} style={{ background: "var(--blue-ink)", color: "#fff" }}>{val("status")}</span> : !collapse && <Hold w={28} />}
                    </motion.div>
                    <Row show={!rowGone(1)} t={layoutT}>{isEmpty("body") ? <Hold w={180} h={16} /> : <p className={`${s.bel} ${s.bbody} m-0 mt-2`} {...hh("body")}><span className={s.clamp5}>{val("body")}</span></p>}</Row>
                    <Row show={!rowGone(2)} t={layoutT}>
                      <div className="flex flex-wrap gap-2 pt-2.5">
                        {isEmpty("log") ? <Hold w={74} h={32} /> : <span className={`mb-btn is-primary ${s.bel}`} {...hh("log")} style={{ height: 32 }}>{P.log?.label}</span>}
                        {isEmpty("deploy") ? <Hold w={68} h={32} /> : <span className={`mb-btn ${s.bel}`} {...hh("deploy")} style={{ height: 32 }}>{act?.label}</span>}
                      </div>
                    </Row>
                  </div>
                </div>
              </motion.div>
            </div>
            <div className="mt-4">
              <button type="button" onClick={sendTest} className="btn btn-ghost btn-sm cursor-pointer gap-2">
                <Send aria-hidden className="size-3.5" /> Send test
              </button>
            </div>
          </article>

          <p className={`readout col-span-full ${s.oline}`} style={{ color: "var(--accent-text)" }} role="status" aria-live="polite" aria-label="Send test outcome">{sent && sent.sig === sig ? sent.msg : ""}</p>
        </div>
      </div>
    </section>
  );
}

/**
 * A banner row that grows and shrinks. The wrapper clips for the height animation, so it carries 6 px of padding
 * pulled back by a -6 px margin: the 2 px focus ring with its 3 px offset (5 px) of every element inside has room.
 */
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
          className={s.row}
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
