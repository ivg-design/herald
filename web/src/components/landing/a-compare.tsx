"use client";
import { useRef, type ReactNode } from "react";
import { motion, useInView, useReducedMotion } from "framer-motion";
import { EASE } from "@/lib/config";

type Row = [label: string, value: ReactNode];

function Never() {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLSpanElement>(null);
  const inView = useInView(ref, { once: true, margin: "0px 0px -15% 0px" });
  const on = reduce || inView;
  return (
    <>
      <span ref={ref} className="relative inline-block">
        Never.
        <motion.span
          aria-hidden
          className="absolute -bottom-[2px] left-0 h-[2px] w-full origin-left bg-accent"
          initial={false}
          animate={{ scaleX: on ? 1 : 0 }}
          transition={reduce ? { duration: 0 } : { duration: 0.6, delay: 0.9, ease: EASE.quint }}
        />
      </span>{" "}
      Not on show, not on click, not on confirm
    </>
  );
}

const MAC: Row[] = [
  ["Lifetime", "Banner fades in ~5 s, or Alert style stays until closed"],
  ["Layout", "Apple’s template only: title, body, thumbnail"],
  ["Actions", "Up to a few buttons, no scripts"],
  ["History", "None. Dismissed or cleared means gone"],
  ["Focus", "Can activate the app on click"],
  ["Grouping", "Per app only"],
];
const HERALD: Row[] = [
  ["Lifetime", "Stays until you dismiss, snooze, or act"],
  ["Layout", "Your 3×4 grid: text, images, badges, progress, Rive"],
  ["Actions", "URLs, callbacks, scripts, Apple Shortcuts, two-way"],
  ["History", "SQLite, searchable, re-show any banner, export"],
  ["Focus", <Never key="never" />],
  ["Grouping", "By app, issuer or sender, stacked with a counter"],
];

function Table({ title, rows, herald }: { title: string; rows: Row[]; herald?: boolean }) {
  const reduce = useReducedMotion();
  const ref = useRef<HTMLTableElement>(null);
  const inView = useInView(ref, { once: true, margin: "0px 0px -20% 0px" });
  const animate = herald && !reduce;
  return (
    <table
      ref={ref}
      className={`w-full overflow-hidden rounded-xl border-collapse text-left text-[14px] ${
        herald ? "border-2 border-accent bg-white" : "border border-paper-line bg-white"
      }`}
      style={{ borderCollapse: "separate", borderSpacing: 0 }}
    >
      <caption className="sr-only">{title}</caption>
      <thead>
        <tr>
          <th
            colSpan={2}
            scope="colgroup"
            className={`h-10 px-[17px] text-[13px] font-semibold ${
              herald ? "bg-accent text-accent-ink" : "bg-[#ecebe6] text-paper-ink/80"
            }`}
          >
            {title}
          </th>
        </tr>
      </thead>
      <tbody>
        {rows.map(([label, value], i) => (
          <tr key={label} className="relative">
            <th
              scope="row"
              className="w-[30%] border-t border-paper-line px-[17px] py-[12px] align-top text-[13px] font-medium text-paper-muted sm:w-[28%]"
            >
              {animate && (
                <motion.span
                  aria-hidden
                  className="pointer-events-none absolute inset-0"
                  style={{ background: "var(--accent-soft)" }}
                  initial={{ opacity: 0 }}
                  animate={inView ? { opacity: [0, 1, 0.0] } : { opacity: 0 }}
                  transition={{ duration: 0.9, delay: i * 0.14, times: [0, 0.35, 1], ease: EASE.quart }}
                />
              )}
              <span className="relative">{label}</span>
            </th>
            <td
              className={`relative border-t border-paper-line px-2 py-[12px] align-top ${
                herald ? "font-medium text-paper-ink" : "text-paper-ink"
              }`}
            >
              {value}
            </td>
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function Comparison() {
  return (
    <div className="mt-14 grid gap-6 md:grid-cols-2">
      <Table title="macOS Notification Center" rows={MAC} />
      <Table title="Herald" rows={HERALD} herald />
    </div>
  );
}
