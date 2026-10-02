import { describe, expect, it } from "vitest";
import { auth, f, j, mintKey, notify, pair } from "./helpers";

describe("scope and validation", () => {
  it("only mints notify-scoped keys", async () => {
    const { token } = await pair();
    for (const scope of ["admin", "device", "*", "notify,admin"]) {
      const r = await f("/v1/device/keys", { method: "POST", headers: auth(token), body: JSON.stringify({ name: "x", scope }) });
      expect(r.status, scope).toBe(400);
    }
  });
  it("rejects command/callback/script/shortcut fields and lists them", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await notify(key, { title: "t", command: "rm -rf /", callback: { url: "https://x" }, script: "a", shortcut: "b", buttons: [], actions: [], foo: 1 });
    expect(r.status).toBe(400);
    const b = await j(r);
    expect(b.error).toBe("forbidden_fields");
    expect(b.fields.sort()).toEqual(["actions", "buttons", "callback", "command", "foo", "script", "shortcut"]);
  });
  it("rejects non-https links and bad speak options", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await notify(key, { title: "t", link: "file:///etc/passwd" })).status).toBe(400);
    expect((await notify(key, { title: "t", link: "javascript:alert(1)" })).status).toBe(400);
    expect((await notify(key, { title: "t", speak: { text: "hi", command: "x" } })).status).toBe(400);
    expect((await notify(key, { title: "t", link: "https://example.com/a", speak: true, allowVoiceReply: false })).status).toBe(202);
    expect((await notify(key, { title: "t", allowVoiceReply: "no" })).status).toBe(400);
  });
  it("caps the body at 32 KB", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await notify(key, { title: "t", body: "x".repeat(40_000) })).status).toBe(413);
  });
  it("requires a title", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    expect((await notify(key, { body: "x" })).status).toBe(400);
  });
});
