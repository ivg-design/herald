import { describe, expect, it } from "vitest";
import { SELF } from "cloudflare:test";
import { auth, mintKey, pair } from "./helpers";

// The relay answers on workers.dev AND on a custom hostname (Cloudflare Custom Domain). Everything it derives about itself
// (OAuth issuer, resource, WWW-Authenticate, audio URLs) must follow the Host of the request: no redeploy to add a domain.
const WD = "https://herald-relay.acme.workers.dev";
const CUSTOM = "https://herald.example.com";
const at = (base: string, path: string, init: RequestInit = {}) => SELF.fetch(base + path, { redirect: "manual", ...init });
const j = async (r: Response) => (await r.json()) as any;
const REDIRECT = "https://chatgpt.example/callback";

describe("the relay follows the Host header", () => {
  it("serves discovery metadata for whichever host was asked", async () => {
    for (const base of [WD, CUSTOM]) {
      for (const p of ["/.well-known/oauth-protected-resource", "/.well-known/oauth-protected-resource/mcp"]) {
        const m = await j(await at(base, p));
        expect(m.resource).toBe(base + "/mcp");
        expect(m.authorization_servers).toEqual([base]);
      }
      const s = await j(await at(base, "/.well-known/oauth-authorization-server"));
      expect(s.issuer).toBe(base);
      expect(s.authorization_endpoint).toBe(base + "/authorize");
      expect(s.token_endpoint).toBe(base + "/token");
      expect(s.registration_endpoint).toBe(base + "/register");
      expect(s.revocation_endpoint).toBe(base + "/revoke");
      expect(JSON.stringify(s)).not.toContain(base === WD ? "example.com" : "workers.dev");
    }
  });

  it("challenges /mcp with the metadata URL of the host that was called", async () => {
    const r = await at(CUSTOM, "/mcp", { method: "POST", body: "{}" });
    expect(r.status).toBe(401);
    expect(r.headers.get("www-authenticate")).toBe(`Bearer resource_metadata="${CUSTOM}/.well-known/oauth-protected-resource"`);
  });

  it("accepts the resource of the host it is called on and rejects the other host's", async () => {
    const reg = await j(await at(CUSTOM, "/register", { method: "POST", body: JSON.stringify({ client_name: "ChatGPT", redirect_uris: [REDIRECT] }) }));
    const q = (resource: string) => new URLSearchParams({
      response_type: "code", client_id: reg.client_id, redirect_uri: REDIRECT, code_challenge: "A".repeat(43), code_challenge_method: "S256", state: "s", resource,
    });
    const bad = await at(CUSTOM, "/authorize?" + q(WD + "/mcp"));
    expect(bad.status).toBe(302);
    expect(new URL(bad.headers.get("location")!).searchParams.get("error")).toBe("invalid_target");
    const good = await at(CUSTOM, "/authorize?" + q(CUSTOM + "/mcp"));
    expect(new URL(good.headers.get("location") ?? "https://x.test").searchParams.get("error")).toBeNull();
    // and the other way round
    const reg2 = await j(await at(WD, "/register", { method: "POST", body: JSON.stringify({ client_name: "ChatGPT", redirect_uris: [REDIRECT] }) }));
    const q2 = new URLSearchParams({ response_type: "code", client_id: reg2.client_id, redirect_uri: REDIRECT, code_challenge: "A".repeat(43), code_challenge_method: "S256", state: "s", resource: CUSTOM + "/mcp" });
    const other = await at(WD, "/authorize?" + q2);
    expect(new URL(other.headers.get("location")!).searchParams.get("error")).toBe("invalid_target");
  });

  it("keeps a paired Mac and its agent keys valid when the address changes (same Worker, same signing secret)", async () => {
    const dev = await pair();                       // paired through the test host, like Herald does at the first deploy
    const key = await mintKey(dev.token, "bot");
    // the device token works on both other hosts
    for (const base of [WD, CUSTOM]) {
      const list = await at(base, "/v1/device/keys", { headers: auth(dev.token) });
      expect(list.status).toBe(200);
      expect((await j(list)).keys.some((k: any) => k.id === key.id)).toBe(true);
    }
    // the agent key sends through the custom hostname and the receipt comes back from either
    const sent = await at(CUSTOM, "/v1/notify", { method: "POST", headers: auth(key.key), body: JSON.stringify({ title: "via custom", notificationId: "n2" }) });
    expect(sent.status).toBe(202);
    const rec = await at(WD, "/v1/receipts/n2", { headers: auth(key.key) });
    expect(rec.status).toBe(200);
  });

  it("reports health on any host", async () => {
    for (const base of [WD, CUSTOM]) expect((await j(await at(base, "/health"))).service).toBe("herald-relay");
  });
});
