"use client";

import { useRef, useState } from "react";
import { Maximize2, X } from "lucide-react";

export interface Hotspot {
  x: number; // percent from the left
  y: number; // percent from the top
}

interface Data {
  src: string;
  src2x?: string;
  darkSrc?: string;
  darkSrc2x?: string;
  alt: string;
  caption?: string;
  width?: number;
  height?: number;
  hotspots?: Hotspot[];
  focus?: number; // percent from the top that a tall capture shows
}

/** A docs screenshot: framed, sized from the manifest (no layout shift), lazy, with a larger view in a dialog. */
export default function Figure({ "data-figure": raw }: { "data-figure"?: string }) {
  const { src, src2x, darkSrc, darkSrc2x, alt, caption, width, height, hotspots, focus } = JSON.parse(raw || "{}") as Data;
  const [dark, setDark] = useState(false);
  const dialog = useRef<HTMLDialogElement>(null);
  const shown = dark && darkSrc ? darkSrc : src;
  const shown2x = dark && darkSrc ? darkSrc2x : src2x;
  const srcSet = shown2x ? `${shown} 1x, ${shown2x} 2x` : undefined;
  // A capture much taller than it is wide (a whole Settings tab) shows its top part; the larger view has all of it.
  const tall = !!width && !!height && height / width > 1.45 && height > 1000;
  const open = () => dialog.current?.showModal();
  const close = () => dialog.current?.close();

  return (
    <figure className="docs-figure" data-tall={tall ? "" : undefined}>
      <div className="docs-figure-frame">
        <button type="button" className="docs-figure-open" onClick={open} aria-label={`Open a larger view: ${alt}`}>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={shown} srcSet={srcSet} alt={alt} width={width} height={height} loading="lazy" decoding="async" style={tall ? { objectPosition: `50% ${focus ?? 0}%` } : undefined} />
          {!tall && hotspots?.map((h, i) => (
            <span key={i} className="docs-figure-spot" style={{ left: `${h.x}%`, top: `${h.y}%` }} aria-hidden>
              {i + 1}
            </span>
          ))}
          <span className="docs-figure-zoom" aria-hidden>
            <Maximize2 size={14} />
            {tall && <span>Show the whole capture</span>}
          </span>
        </button>
      </div>
      {(caption || darkSrc) && (
        <figcaption>
          {caption && <span>{caption}</span>}
          {darkSrc && (
            <span className="docs-figure-modes" role="group" aria-label="Appearance">
              <button type="button" aria-pressed={!dark} onClick={() => setDark(false)}>light</button>
              <button type="button" aria-pressed={dark} onClick={() => setDark(true)}>dark</button>
            </span>
          )}
        </figcaption>
      )}
      <dialog ref={dialog} className="docs-lightbox" aria-label={alt} onClick={(e) => { if (e.target === dialog.current) close(); }}>
        <div className="docs-lightbox-in">
          <button type="button" className="docs-lightbox-close" onClick={close} aria-label="Close the larger view">
            <X size={18} aria-hidden />
          </button>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={shown2x ?? shown} alt={alt} width={width} height={height} loading="lazy" decoding="async" />
          {caption && <p>{caption}</p>}
        </div>
      </dialog>
    </figure>
  );
}
