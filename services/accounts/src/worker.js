import { createRemoteJWKSet, jwtVerify } from 'jose';
import { validDocument } from './policy.js';

const keySets = new Map();
const json = (body, status = 200) => Response.json(body, { status, headers: {
  'Cache-Control': 'no-store', 'X-Content-Type-Options': 'nosniff',
  'Strict-Transport-Security': 'max-age=31536000',
}});

// Pass a verifier only in unit tests, never through the request or environment.
export function createService(verify = jwtVerify) {
  return { async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === '/health' && request.method === 'GET') return json({ status: 'ok' });
    if (url.pathname !== '/v1/me/settings') return json({ error: 'not_found' }, 404);
    if (!['GET', 'PUT', 'DELETE'].includes(request.method)) return json({ error: 'method_not_allowed' }, 405);
    // There are no cookie sessions or permissive CORS headers. Only bearer tokens
    // from the native public client, validated against Auth0's signing keys.
    const authorization = request.headers.get('Authorization') ?? '';
    if (!/^Bearer [^\s]{1,16384}$/.test(authorization)) return json({ error: 'unauthorized' }, 401);
    if (!env.DB || !env.ACCOUNT_RATE_LIMITER) return json({ error: 'unavailable' }, 503);
    // Cloudflare sets this header; never persist IP addresses or log tokens.
    const ip = request.headers.get('CF-Connecting-IP');
    try {
      if (ip && !(await env.ACCOUNT_RATE_LIMITER.limit({ key: `ip:${ip}` })).success)
        return json({ error: 'rate_limited' }, 429);
    } catch { return json({ error: 'unavailable' }, 503); }
    let identity;
    try {
      const issuer = new URL(env.AUTH0_ISSUER);
      if (issuer.protocol !== 'https:' || issuer.pathname !== '/') throw new Error('Invalid issuer');
      if (!keySets.has(issuer.href)) keySets.set(issuer.href,
        createRemoteJWKSet(new URL('.well-known/jwks.json', issuer)));
      const { payload } = await verify(authorization.slice(7), keySets.get(issuer.href), {
        issuer: issuer.href, audience: env.AUTH0_AUDIENCE, algorithms: ['RS256'],
        requiredClaims: ['sub', 'iat', 'exp', 'azp'], clockTolerance: 5,
      });
      if (typeof payload.sub !== 'string' || payload.sub.length > 255 || payload.sub.length === 0 ||
          payload.azp !== env.AUTH0_NATIVE_CLIENT_ID || payload.sub.endsWith('@clients')) throw new Error('Invalid user');
      const scopes = new Set(typeof payload.scope === 'string' ? payload.scope.split(' ') : []);
      const required = request.method === 'GET' ? 'read:settings' : 'write:settings';
      if (!scopes.has(required)) return json({ error: 'forbidden' }, 403);
      // Populated by the tenant's post-login Action, never from a request body.
      if (payload['https://notsoboringnotch.app/email_verified'] !== true)
        return json({ error: 'verify_email' }, 403);
      identity = payload.sub;
    } catch { return json({ error: 'unauthorized' }, 401); }
    try {
      const limit = await env.ACCOUNT_RATE_LIMITER.limit({ key: `user:${identity}` });
      if (!limit.success) return json({ error: 'rate_limited' }, 429);
      const current = () => env.DB.prepare('SELECT revision, document, updated_at FROM settings WHERE subject = ?').bind(identity).first();
      if (request.method === 'GET') {
        const row = await current();
        return json(row ? { revision: row.revision, settings: JSON.parse(row.document), updatedAt: row.updated_at } :
          { revision: 0, settings: null, updatedAt: null });
      }
      const match = request.headers.get('If-Match');
      if (!match || !/^"(0|[1-9]\d{0,9})"$/.test(match)) return json({ error: 'precondition_required' }, 428);
      const expected = Number(match.slice(1, -1));
      if (request.method === 'DELETE') {
        const result = await env.DB.prepare('DELETE FROM settings WHERE subject = ? AND revision = ?').bind(identity, expected).run();
        if (!result.meta.changes && (await current())) return json({ error: 'conflict' }, 409);
        return json({ revision: 0, settings: null, updatedAt: null });
      }
      if (request.headers.get('Content-Type')?.split(';')[0].trim().toLowerCase() !== 'application/json') return json({ error: 'invalid_document' }, 400);
      // Limit streamed bodies too; Content-Length alone is not a security boundary.
      const reader = request.body?.getReader();
      if (!reader) return json({ error: 'invalid_document' }, 400);
      let bytes = 0;
      const chunks = [];
      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        bytes += value.length;
        if (bytes > 8192) { await reader.cancel(); return json({ error: 'too_large' }, 413); }
        chunks.push(value);
      }
      const combined = new Uint8Array(bytes);
      let offset = 0;
      for (const chunk of chunks) { combined.set(chunk, offset); offset += chunk.length; }
      let document;
      try { document = JSON.parse(new TextDecoder('utf-8', { fatal: true }).decode(combined)); }
      catch { return json({ error: 'invalid_document' }, 400); }
      if (!validDocument(document)) return json({ error: 'invalid_document' }, 400);
      const updated = new Date().toISOString();
      const result = expected === 0 ? await env.DB.prepare(`INSERT INTO settings(subject, revision, document, updated_at)
        VALUES (?, 1, ?, ?) ON CONFLICT(subject) DO NOTHING`)
        .bind(identity, JSON.stringify(document), updated).run() :
        await env.DB.prepare(`UPDATE settings SET revision = revision + 1, document = ?, updated_at = ?
          WHERE subject = ? AND revision = ?`).bind(JSON.stringify(document), updated, identity, expected).run();
      if (!result.meta.changes) return json({ error: 'conflict' }, 409);
      return json({ revision: expected + 1, settings: document, updatedAt: updated });
    } catch { return json({ error: 'unavailable' }, 503); }
  }};
}
export default createService();
