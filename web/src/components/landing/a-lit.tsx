"use client";
import { createContext, useContext, useEffect, useState, type ReactNode } from "react";
import { motion, useReducedMotion, useTransform, type MotionValue } from "framer-motion";

const Ctx = createContext<{ p: MotionValue<number>; live: boolean } | null>(null);

/** Provides scroll progress. `live` is false until hydrated and only true when motion is allowed,
 *  so the default (SSR, no JS, reduced motion) is the final lit state. */
export function LitProvider({ progress, children }: { progress: MotionValue<number>; children: ReactNode }) {
  const reduce = useReducedMotion();
  const [live, setLive] = useState(false);
  useEffect(() => setLive(!reduce), [reduce]);
  return <Ctx.Provider value={{ p: progress, live }}>{children}</Ctx.Provider>;
}

/** Lights up (opacity from `dim` to 1, optional 8 px rise) between scroll progress `from` and `to`. */
export function Lit({
  from,
  to,
  dim = 0.28,
  rise = 0,
  className,
  style,
  children,
  ...rest
}: {
  from: number;
  to: number;
  dim?: number;
  rise?: number;
  className?: string;
  style?: React.CSSProperties;
  children?: ReactNode;
  "aria-hidden"?: boolean;
}) {
  const ctx = useContext(Ctx);
  const fallback = useTransform(() => 1);
  const opacity = useTransform(ctx?.p ?? fallback, [from, to], [dim, 1], { clamp: true });
  const y = useTransform(ctx?.p ?? fallback, [from, to], [rise, 0], { clamp: true });
  return (
    <motion.span
      className={className}
      style={ctx?.live ? { ...style, opacity, y: rise ? y : 0 } : style}
      {...rest}
    >
      {children}
    </motion.span>
  );
}
