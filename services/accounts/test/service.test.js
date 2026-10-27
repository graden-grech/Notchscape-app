import test from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import { runInNewContext } from 'node:vm';
import { createLocalJWKSet, exportJWK, generateKeyPair, jwtVerify, SignJWT } from 'jose';
import { createService } from '../src/worker.js';
import { validDocument, booleans, choices, lists } from '../src/policy.js';

const issuer = 'https://test.us.auth0.com/';
const audience = 'https://notsoboringnotch.app/settings';
const client = 'native-client';
const { privateKey, publicKey } = await generateKeyPair('RS256');
const jwk = await exportJWK(publicKey);
const keys = createLocalJWKSet({ keys: [{ ...jwk, kid: 'test', alg: 'RS256' }] });
const service = createService((token, _remoteKeys, options) => jwtVerify(token, keys, options));
const document = { schemaVersion: 1, values: { appTheme: 'christmas', showBatteryPercentage: true } };
async function token(sub = 'auth0|alice', extra = {}, options = {}) {
  return new SignJWT({ azp: client, scope: 'read:settings write:settings',
    'https://notsoboringnotch.app/email_verified': true, ...extra })
    .setProtectedHeader({ alg: 'RS256', kid: 'test' }).setIssuer(options.issuer ?? issuer)
    .setAudience(options.audience ?? audience).setSubject(sub).setIssuedAt()
    .setExpirationTime(options.expiry ?? '5m').sign(privateKey);
}
function environment() {
  const db = new DatabaseSync(':memory:');
  db.exec(readFileSync(new URL('../migrations/0001_settings.sql', import.meta.url), 'utf8'));
  return {
    AUTH0_ISSUER: issuer, AUTH0_AUDIENCE: audience, AUTH0_NATIVE_CLIENT_ID: client,
    ACCOUNT_RATE_LIMITER: { limit: async () => ({ success: true }) },
    DB: { prepare(sql) { return { bind(...params) { return {
      first: async () => db.prepare(sql).get(...params) ?? null,
      run: async () => ({ meta: { changes: db.prepare(sql).run(...params).changes } }),
    }; } }; } },
  };
}
async function request(env, auth, method = 'GET', body, revision, extraHeaders = {}) {
  return service.fetch(new Request('https://settings.example/v1/me/settings', {
    method, headers: { ...(auth ? { Authorization: `Bearer ${auth}` } : {}),
      ...(revision !== undefined ? { 'If-Match': `"${revision}"` } : {}),
      ...(body !== undefined ? { 'Content-Type': 'application/json' } : {}), ...extraHeaders },
    ...(body !== undefined ? { body: JSON.stringify(body) } : {}),
  }), env);
}

test('strict appearance schema rejects executable, privileged and private fields', () => {
  for (const key of booleans) {
    assert.ok(validDocument({ schemaVersion: 1, values: { [key]: true } }));
    for (const invalid of [1, 'true', null, {}, []])
      assert.equal(validDocument({ schemaVersion: 1, values: { [key]: invalid } }), false);
  }
  for (const [key, values] of Object.entries(choices))
    for (const value of values) assert.ok(validDocument({ schemaVersion: 1, values: { [key]: value } }));
  for (const key of lists) {
    assert.ok(validDocument({ schemaVersion: 1, values: { [key]: ['music', 'calendar'] } }));
    assert.equal(validDocument({ schemaVersion: 1, values: { [key]: ['music', 'music'] } }), false);
  }
  for (const key of ['admin', 'role', 'permissions', '__proto__', 'hudReplacement', 'quickActions', 'agentHistory', 'location'])
    assert.equal(validDocument(JSON.parse(`{"schemaVersion":1,"values":{"${key}":true}}`)), false);
  assert.equal(validDocument({ ...document, admin: true }), false);
  assert.equal(validDocument({ schemaVersion: 2, values: {} }), false);
  assert.equal(validDocument({ schemaVersion: 1, values: { appTheme: 'DROP TABLE users;' } }), false);
});

test('no token, malformed token, wrong issuer/audience/client, expiry and unverified email fail closed', async () => {
  const env = environment();
  for (const auth of [undefined, 'not-a-token', await token('auth0|alice', {}, { issuer: 'https://evil.example/' }),
    await token('auth0|alice', {}, { audience: 'other-api' }), await token('auth0|alice', { azp: 'other-client' }),
    await token('auth0|alice', {}, { expiry: 1 }), await token('machine@clients')]) {
    assert.equal((await request(env, auth)).status, 401);
  }
  assert.equal((await request(env, await token('auth0|alice', { 'https://notsoboringnotch.app/email_verified': false }))).status, 403);
  assert.equal((await request(env, await token('auth0|alice', { scope: 'openid' }))).status, 403);
  assert.equal((await request(env, await token('auth0|alice', { scope: 'read:settings' }), 'PUT', document, 0)).status, 403);
});

test('forged signatures, algorithm substitution and missing required claims fail closed', async () => {
  const env = environment();
  const valid = await token();
  const parts = valid.split('.');
  parts[1] = Buffer.from(JSON.stringify({ ...JSON.parse(Buffer.from(parts[1], 'base64url')),
    sub: 'auth0|someone-else' })).toString('base64url');
  const forgedPayload = parts.join('.');
  const { privateKey: otherKey } = await generateKeyPair('RS256');
  const claims = { iss: issuer, aud: audience, sub: 'auth0|alice', azp: client,
    iat: Math.floor(Date.now() / 1000), exp: Math.floor(Date.now() / 1000) + 300,
    scope: 'read:settings write:settings', 'https://notsoboringnotch.app/email_verified': true };
  const wrongKey = await new SignJWT(claims).setProtectedHeader({ alg: 'RS256', kid: 'test' }).sign(otherKey);
  const wrongAlgorithm = await new SignJWT(claims).setProtectedHeader({ alg: 'HS256', kid: 'test' })
    .sign(new TextEncoder().encode('synthetic-test-only-shared-secret'));
  const unsigned = `${Buffer.from('{"alg":"none"}').toString('base64url')}.${valid.split('.')[1]}.`;
  for (const forged of [forgedPayload, wrongKey, wrongAlgorithm, unsigned])
    assert.equal((await request(env, forged)).status, 401);
  for (const key of ['sub', 'iat', 'exp', 'azp']) {
    const incomplete = { ...claims };
    delete incomplete[key];
    const auth = await new SignJWT(incomplete).setProtectedHeader({ alg: 'RS256', kid: 'test' }).sign(privateKey);
    assert.equal((await request(env, auth)).status, 401);
  }
});

test('settings are isolated by verified subject, not names, roles or guessed IDs', async () => {
  const env = environment();
  const alice = await token('auth0|alice', { name: 'admin', role: 'admin' });
  const bob = await token('auth0|bob', { name: 'DROP TABLE settings;--' });
  assert.equal((await request(env, alice, 'PUT', document, 0)).status, 200);
  assert.equal((await (await request(env, bob)).json()).settings, null);
  assert.equal((await request(env, bob, 'PUT', { ...document, subject: 'auth0|alice' }, 0)).status, 400);
  assert.equal((await request(env, bob, 'PUT', document, 0)).status, 200);
  assert.deepEqual((await (await request(env, alice)).json()).settings, document);
});

test('SQL-looking subject remains bound data and cannot delete another user', async () => {
  const env = environment();
  const alice = await token();
  const injection = await token("auth0|x'; DROP TABLE settings;--");
  assert.equal((await request(env, alice, 'PUT', document, 0)).status, 200);
  assert.equal((await request(env, injection, 'PUT', document, 0)).status, 200);
  assert.equal((await request(env, injection, 'DELETE', undefined, 1)).status, 200);
  assert.deepEqual((await (await request(env, alice)).json()).settings, document);
});

test('optimistic concurrency prevents silent overwrites and stale deletes', async () => {
  const env = environment(), auth = await token();
  assert.equal((await request(env, auth, 'PUT', document)).status, 428);
  assert.equal((await request(env, auth, 'PUT', document, 0)).status, 200);
  assert.equal((await request(env, auth, 'PUT', document, 0)).status, 409);
  assert.equal((await request(env, auth, 'PUT', document, 1)).status, 200);
  assert.equal((await request(env, auth, 'PUT', document, 1)).status, 409);
  assert.equal((await request(env, auth, 'DELETE', undefined, 1)).status, 409);
  assert.equal((await (await request(env, auth)).json()).revision, 2);
  assert.equal((await request(env, auth, 'DELETE', undefined, 2)).status, 200);
  assert.equal((await (await request(env, auth)).json()).settings, null);
});

test('bounded body, strict schema, rate limiting, and unavailable bindings are enforced', async () => {
  const env = environment(), auth = await token();
  assert.equal((await request(env, auth, 'PUT', { schemaVersion: 1, values: { appTheme: 'x'.repeat(10_000) } }, 0)).status, 413);
  assert.equal((await request(env, auth, 'PUT', { schemaVersion: 1, values: { hudReplacement: true } }, 0)).status, 400);
  env.ACCOUNT_RATE_LIMITER = { limit: async () => ({ success: false }) };
  assert.equal((await request(env, auth)).status, 429);
  delete env.ACCOUNT_RATE_LIMITER;
  assert.equal((await request(env, auth)).status, 503);
});

test('responses are not cached or exposed to arbitrary browser origins', async () => {
  const response = await request(environment(), await token());
  assert.equal(response.headers.get('Cache-Control'), 'no-store');
  assert.equal(response.headers.get('Access-Control-Allow-Origin'), null);
  assert.equal(response.headers.get('X-Content-Type-Options'), 'nosniff');
});

test('login action trusts provider verification, never a name or editable metadata', async () => {
  const sandbox = { exports: {} };
  runInNewContext(readFileSync(new URL('../auth0/post-login.js', import.meta.url), 'utf8'), sandbox);
  for (const verified of [true, false, undefined, 'true', 1]) {
    let claim;
    await sandbox.exports.onExecutePostLogin({ user: { email_verified: verified,
      name: 'admin', user_metadata: { admin: true, email_verified: true } } },
    { accessToken: { setCustomClaim: (key, value) => { claim = { key, value }; } } });
    assert.deepEqual(claim, { key: 'https://notsoboringnotch.app/email_verified', value: verified === true });
  }
});
