#!/usr/bin/env node
'use strict';
/**
 * Herald client, zero dependencies (Node 18+, global fetch). CommonJS, importable from ESM:
 *   const { Herald } = require('./herald.js');   // CJS
 *   import herald from './herald.js'; const { Herald } = herald;   // ESM default import
 *   import { Herald } from './herald.js';   // ESM named import (cjs-module-lexer detects it)
 *
 *   const h = new Herald();
 *   if (await h.isAvailable()) {
 *     await h.notify('bidbot', 'Bid accepted', { body: 'Won', id: 'bid-42', url: 'https://example.com' });
 *     await h.dismiss('bidbot', 'bid-42');
 *   }
 * Rejects with HeraldUnavailable when Herald is not running.
 */
const fs = require('fs');
const os = require('os');
const path = require('path');

const SUPPORT_DIR = path.join(os.homedir(), 'Library', 'Application Support', 'Herald');
const DEFAULT_PORT = 48617;

class HeraldError extends Error {
  constructor(status, message) { super(`Herald error ${status}: ${message}`); this.name = 'HeraldError'; this.status = status; }
}
class HeraldUnavailable extends HeraldError {
  constructor(message = 'Herald is not running. Launch Herald.app first.') {
    super(0, message); this.name = 'HeraldUnavailable'; this.message = message;
  }
}

function readTrim(name) {
  try { return fs.readFileSync(path.join(SUPPORT_DIR, name), 'utf8').trim() || null; } catch { return null; }
}

class Herald {
  /** @param {{port?: number, token?: string, timeoutMs?: number}} [opts] */
  constructor({ port, token, timeoutMs = 10000 } = {}) {
    const pf = readTrim('port');
    this.port = port || (pf && /^\d+$/.test(pf) ? Number(pf) : DEFAULT_PORT);
    this._token = token || null;
    this.timeoutMs = timeoutMs;
  }
  get token() { return this._token || readTrim('token'); }
  get baseUrl() { return `http://127.0.0.1:${this.port}`; }

  async _request(method, p, { body, query, auth = true } = {}) {
    let url = this.baseUrl + p;
    if (query) {
      const q = new URLSearchParams();
      for (const [k, v] of Object.entries(query)) if (v != null) q.set(k, String(v));
      url += '?' + q.toString();
    }
    const headers = {};
    if (body !== undefined) headers['Content-Type'] = 'application/json';
    const token = auth ? this.token : null;
    if (token) headers.Authorization = `Bearer ${token}`;
    let res;
    try {
      res = await fetch(url, {
        method, headers, body: body === undefined ? undefined : JSON.stringify(body),
        signal: AbortSignal.timeout(this.timeoutMs),
      });
    } catch (e) {
      throw new HeraldUnavailable();
    }
    const text = await res.text();
    let json = {};
    try { json = text ? JSON.parse(text) : {}; } catch { json = { error: text }; }
    if (!res.ok) throw new HeraldError(res.status, json.error || text);
    return json;
  }

  async isAvailable() {
    try { return !!(await this._request('GET', '/v1/health', { auth: false })).ok; }
    catch (e) { if (e instanceof HeraldError) return false; throw e; }
  }
  health() { return this._request('GET', '/v1/health', { auth: false }); }
  /** @returns {Promise<string>} the notification id */
  async notify(app, title, fields = {}) {
    const r = await this._request('POST', '/v1/notify', { body: { app, title, ...fields } });
    return r.id ?? fields.id;
  }
  register(app, fields = {}) { return this._request('POST', '/v1/register', { body: { app, ...fields } }); }
  dismiss(app, id) { return this._request('POST', '/v1/dismiss', { body: { app, id } }); }
  dismissAll(app) { return this._request('POST', '/v1/dismissAll', { body: { app } }); }
  async history(app, limit = 50) { return (await this._request('GET', '/v1/history', { query: { app, limit } })).items || []; }
  clearHistory(app) { return this._request('DELETE', '/v1/history', { query: { app } }); }
  apps() { return this._request('GET', '/v1/apps'); }
}

module.exports = { Herald, HeraldError, HeraldUnavailable, default: { Herald, HeraldError, HeraldUnavailable } };
module.exports.Herald = Herald;
module.exports.HeraldError = HeraldError;
module.exports.HeraldUnavailable = HeraldUnavailable;

if (require.main === module) {
  new Herald().notify('herald-demo', 'Hello from Node', {
    body: 'Herald client demo. [Docs](https://example.com)', sound: 'Glass', snooze: true,
    buttons: [{ label: 'Open', url: 'https://example.com' }],
  }).then((id) => console.log('sent', id)).catch((e) => {
    console.error(e.message); process.exit(e instanceof HeraldUnavailable ? 2 : 1);
  });
}
