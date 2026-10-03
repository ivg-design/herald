"use client";
// Self-host the Rive runtime wasm (public/rive/rive.wasm) instead of the default unpkg URL.
// Imported for its side effect by StatusRing and Bell; runs once, client-side only.
import { RuntimeLoader } from "@rive-app/react-canvas";
import { asset } from "@/lib/config";

let done = false;
if (typeof window !== "undefined" && !done) {
  done = true;
  RuntimeLoader.setWasmUrl(asset("/rive/rive.wasm"));
}
