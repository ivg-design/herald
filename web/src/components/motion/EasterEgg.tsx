"use client";

import { useEffect } from "react";
import { useHerald } from "@/components/herald/useHerald";

/** Cmd/Ctrl+Shift+H sends a banner to the page's Herald. Renders nothing. */
export default function EasterEgg() {
  const { send } = useHerald();
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (!(e.metaKey || e.ctrlKey) || !e.shiftKey || e.key.toLowerCase() !== "h") return;
      const el = e.target as HTMLElement | null;
      if (el && (el.isContentEditable || /^(INPUT|TEXTAREA|SELECT)$/.test(el.tagName))) return;
      e.preventDefault();
      send({
        app: "herald",
        appName: "Herald",
        icon: "herald",
        title: "You found it.",
        body: "Banners that stay until you decide. Snooze this one and it comes back in 10 s.",
        buttons: [
          { label: "Snooze", role: "snooze" },
          { label: "Dismiss", role: "dismiss" },
        ],
        snooze: { seconds: 10, label: "in 10 s" },
      });
    };
    window.addEventListener("keydown", onKey);
    return () => window.removeEventListener("keydown", onKey);
  }, [send]);
  return null;
}
