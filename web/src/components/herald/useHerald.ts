"use client";
import { createContext, useContext } from "react";
import type { HeraldApi } from "./types";

export const HeraldContext = createContext<HeraldApi | null>(null);

/** The page's Herald. Throws outside <HeraldHost>. */
export function useHerald(): HeraldApi {
  const api = useContext(HeraldContext);
  if (!api) throw new Error("useHerald() needs <HeraldHost> above it");
  return api;
}
