"use client";
// STUB - owned by worker D. Contract: <WordSwapper words={[...]} staticWord="do things" /> renders the cycling word
// (LERP-style: ~2.2 s hold, 400 ms ease-out-quint, pause on hover, reduced-motion shows staticWord). Also exports
// the active index through onIndex so the "rotates:" chips can highlight it.
export default function WordSwapper({ words, staticWord, onIndex }: { words: string[]; staticWord: string; onIndex?: (i: number) => void; className?: string }) {
  void onIndex;
  return <span>{words[0] ?? staticWord}</span>;
}
