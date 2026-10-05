import { describe, expect, it } from "vitest";
import { auth, connect, f, mintKey, notify, pair } from "./helpers";

const j = async (r: Response) => (await r.json()) as any;
const PNG = "data:image/png;base64,iVBORw0KGgo=";

async function sendAndReceive(body: Record<string, unknown>) {
  const { token } = await pair();
  const { key } = await mintKey(token);
  const ws = await connect(token);
  const r = await notify(key, { title: "t", ...body });
  expect(r.status).toBe(202);
  return (await ws.next("notify")).payload;
}

describe("presentation fields reach the Mac", () => {
  it("persistent, timeoutSeconds, sound, priority, group, subtitle", async () => {
    const p = await sendAndReceive({ persistent: true, timeoutSeconds: 30, sound: "Glass", priority: "high", group: "ci", subtitle: "main" });
    expect(p).toMatchObject({ persistent: true, timeoutSeconds: 30, sound: "Glass", priority: "high", group: "ci", subtitle: "main" });
  });
  it("sound none and default", async () => {
    expect((await sendAndReceive({ sound: "none" })).sound).toBe("none");
    expect((await sendAndReceive({ sound: "default" })).sound).toBe("default");
  });
  it("speak as true, as text, as an object", async () => {
    expect((await sendAndReceive({ speak: true })).speak).toBe(true);
    expect((await sendAndReceive({ speak: "Build finished" })).speak).toEqual({ text: "Build finished" });
    expect((await sendAndReceive({ speak: { text: "hi", voice: "af_heart", speed: 1.2 } })).speak).toEqual({ text: "hi", voice: "af_heart", speed: 1.2 });
  });
  it("voice and speed beside speak merge into it, and alone they turn speaking on", async () => {
    expect((await sendAndReceive({ speak: true, voice: "bf_emma", speed: 0.9 })).speak).toEqual({ voice: "bf_emma", speed: 0.9 });
    expect((await sendAndReceive({ voice: "am_michael" })).speak).toEqual({ voice: "am_michael" });
    expect((await sendAndReceive({ speak: { voice: "af_bella" }, voice: "bf_emma" })).speak).toEqual({ voice: "af_bella" });
  });
  it("an explicit speak: false wins over voice, speed and presentation", async () => {
    for (const extra of [{ voice: "af_heart" }, { speed: 1.2 }, { voice: "af_heart", speed: 1.2, presentation: "both" }, { presentation: "voice" }]) {
      const got = await sendAndReceive({ speak: false, ...extra });
      expect(got.speak, JSON.stringify(extra)).toBeUndefined();
    }
  });
  it("presentation voice or both implies speak", async () => {
    const v = await sendAndReceive({ presentation: "voice" });
    expect(v).toMatchObject({ presentation: "voice", speak: true });
    expect(await sendAndReceive({ presentation: "both", speak: "x" })).toMatchObject({ presentation: "both", speak: { text: "x" } });
    const b = await sendAndReceive({ presentation: "banner" });
    expect(b.presentation).toBe("banner");
    expect(b.speak).toBeUndefined();
  });
  it("icon (https and data:), imageURL, tags", async () => {
    expect((await sendAndReceive({ icon: PNG })).icon).toBe(PNG);
    expect((await sendAndReceive({ icon: "https://example.com/i.png" })).icon).toBe("https://example.com/i.png");
    const p = await sendAndReceive({ imageURL: "https://example.com/shot.png", tags: ["ci", "main", "ci"] });
    expect(p.imageURL).toBe("https://example.com/shot.png");
    expect(p.tags).toEqual(["ci", "main"]);
  });
  it("a data: icon up to 256 KB is accepted past the 32 KB body limit; more is refused", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const big = (n: number) => "data:image/png;base64," + "A".repeat(Math.ceil(n * 4 / 3));
    expect((await notify(key, { title: "t", icon: big(200 * 1024) })).status).toBe(202);
    const over = await notify(key, { title: "t", icon: big(260 * 1024) });
    expect(over.status).toBe(400);
    expect((await j(over)).fields).toEqual(["icon"]);
    // the rest of the request still has to fit the normal limit
    expect((await notify(key, { title: "t", body: "x".repeat(7000), subtitle: "s", icon: big(100 * 1024) })).status).toBe(202);
    const r = await f("/v1/notify", { method: "POST", headers: auth(key), body: JSON.stringify({ title: "t", body: "x".repeat(40_000), icon: big(10 * 1024) }) });
    expect([400, 413]).toContain(r.status);
  });
});

describe("presentation fields are validated", () => {
  it.each([
    [{ persistent: "yes" }, "persistent"],
    [{ timeoutSeconds: 0 }, "timeoutSeconds"],
    [{ timeoutSeconds: 99999 }, "timeoutSeconds"],
    [{ timeoutSeconds: "5" }, "timeoutSeconds"],
    [{ sound: "/System/Library/Sounds/Glass.aiff" }, "sound"],
    [{ sound: "../x" }, "sound"],
    [{ presentation: "popup" }, "presentation"],
    [{ priority: "critical" }, "priority"],
    [{ voice: "af heart; rm" }, "voice"],
    [{ speed: 5 }, "speed"],
    [{ icon: "http://example.com/i.png" }, "icon"],
    [{ icon: "file:///etc/passwd" }, "icon"],
    [{ icon: "data:text/html;base64,PGI+" }, "icon"],
    [{ icon: "javascript:alert(1)" }, "icon"],
    [{ imageURL: "http://example.com/a.png" }, "imageURL"],
    [{ imageURL: "/Users/me/a.png" }, "imageURL"],
    [{ tags: "ci" }, "tags"],
    [{ tags: Array(11).fill("a") }, "tags"],
    [{ tags: ["a,b"] }, "tags"],
    [{ speak: 5 }, "speak"],
  ])("%j is a 400 naming %s", async (body, field) => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await notify(key, { title: "t", ...body });
    expect(r.status).toBe(400);
    expect((await j(r)).fields).toContain(field);
  });

  it("anything executable is a 400 that lists every stripped key", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const r = await notify(key, {
      title: "t", persistent: true, command: "rm -rf /", script: "a.sh", shortcut: "Run", callback: { url: "https://x.example" }, webhook: "https://x",
      buttons: [{ label: "Go", url: "https://x.example" }], actions: [], actionIds: ["a"], url: "https://x.example", image: "/etc/passwd",
      audio: "/tmp/a.wav", template: "t", app: "x", reminder: { title: "r" }, metadata: { a: 1 },
    });
    expect(r.status).toBe(400);
    const b = await j(r);
    expect(b.error).toBe("forbidden_fields");
    expect(b.fields.sort()).toEqual(["actionIds", "actions", "app", "audio", "buttons", "callback", "command", "image", "metadata", "reminder", "script", "shortcut", "template", "url", "webhook"]);
    expect(b.message).toContain("would run or open something");
  });

  it("expectReply adds nothing else to the payload: no status, no persistence change", async () => {
    const p = await sendAndReceive({ expectReply: true });
    expect(p).toEqual({ title: "t", expectReply: true });
    const q = await sendAndReceive({});
    expect(q).toEqual({ title: "t", expectReply: false });
  });
});

describe("MCP send_notification", () => {
  it("lists every presentation field and passes them through", async () => {
    const { token } = await pair();
    const { key } = await mintKey(token);
    const ws = await connect(token);
    const rpc = (b: unknown) => f("/mcp", { method: "POST", headers: auth(key), body: JSON.stringify(b) });
    const tools = (await j(await rpc({ jsonrpc: "2.0", id: 1, method: "tools/list" }))).result.tools;
    const send = tools.find((t: any) => t.name === "send_notification");
    for (const k of ["persistent", "timeoutSeconds", "sound", "speak", "voice", "speed", "presentation", "priority", "group", "icon", "subtitle", "imageURL", "tags", "expectReply"]) {
      expect(send.inputSchema.properties[k], k).toBeTruthy();
    }
    expect(send.inputSchema.properties.expectReply.description).toContain("Only adds the Reply");
    expect(send.description).toContain('"speak":true,"persistent":true');
    const call = await j(await rpc({ jsonrpc: "2.0", id: 2, method: "tools/call", params: { name: "send_notification", arguments: { title: "spoken", speak: true, persistent: true } } }));
    expect(call.result.isError).toBeUndefined();
    expect((await ws.next("notify")).payload).toMatchObject({ title: "spoken", speak: true, persistent: true });
    const init = await j(await rpc({ jsonrpc: "2.0", id: 3, method: "initialize", params: { protocolVersion: "2025-06-18" } }));
    expect(init.result.instructions).toContain("device flow");
  });
});
