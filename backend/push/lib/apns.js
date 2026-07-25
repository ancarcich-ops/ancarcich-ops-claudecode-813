// APNs delivery over raw HTTP/2 with token-based (.p8) auth.
// Zero dependencies — uses node:http2 and node:crypto only.
//
// Env vars required:
//   APNS_KEY      — contents of the .p8 file (literal \n sequences OK)
//   APNS_KEY_ID   — 10-char key id
//   APNS_TEAM_ID  — Apple Developer team id
//
// Topic (bundle id) is fixed for Sticks.

import http2 from "node:http2";
import crypto from "node:crypto";

export const APNS_TOPIC = "app.rork.ofo2zt4lcp6hi4ceu1jsm";

const HOSTS = {
  production: "https://api.push.apple.com",
  sandbox: "https://api.sandbox.push.apple.com",
};

const JWT_TTL_SECONDS = 50 * 60; // Apple wants 20–60 min; refresh at 50.

let cachedJwt = null;
let cachedJwtIssuedAt = 0;

function base64url(input) {
  return Buffer.from(input)
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");
}

/** Returns a cached ES256 provider JWT, re-signing every ~50 minutes. */
function apnsJwt() {
  const now = Math.floor(Date.now() / 1000);
  if (cachedJwt && now - cachedJwtIssuedAt < JWT_TTL_SECONDS) return cachedJwt;

  const key = (process.env.APNS_KEY ?? "").replace(/\\n/g, "\n");
  const keyId = process.env.APNS_KEY_ID;
  const teamId = process.env.APNS_TEAM_ID;
  if (!key || !keyId || !teamId) {
    throw new Error("APNS_KEY / APNS_KEY_ID / APNS_TEAM_ID env vars are not configured");
  }

  const header = base64url(JSON.stringify({ alg: "ES256", kid: keyId }));
  const claims = base64url(JSON.stringify({ iss: teamId, iat: now }));
  const signingInput = `${header}.${claims}`;
  // JWT ES256 needs the raw r||s signature, not DER.
  const signature = crypto
    .sign("sha256", Buffer.from(signingInput), { key, dsaEncoding: "ieee-p1363" })
    .toString("base64")
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  cachedJwt = `${signingInput}.${signature}`;
  cachedJwtIssuedAt = now;
  return cachedJwt;
}

/** Sends one push on an open HTTP/2 session. Resolves with { status, reason }. */
function sendOne(session, jwt, deviceToken, body, headers) {
  return new Promise((resolve) => {
    const req = session.request({
      ":method": "POST",
      ":path": `/3/device/${deviceToken}`,
      authorization: `bearer ${jwt}`,
      "apns-topic": APNS_TOPIC,
      "apns-push-type": "alert",
      "apns-priority": "10",
      "content-type": "application/json",
      ...headers,
    });

    let status = 0;
    let data = "";
    req.setEncoding("utf8");
    req.on("response", (h) => {
      status = h[":status"] ?? 0;
    });
    req.on("data", (chunk) => {
      data += chunk;
    });
    req.on("end", () => {
      let reason = null;
      if (data) {
        try {
          reason = JSON.parse(data).reason ?? null;
        } catch {
          reason = null;
        }
      }
      resolve({ status, reason });
    });
    req.on("error", (err) => {
      resolve({ status: 0, reason: `stream_error:${err.code ?? err.message}` });
    });
    req.setTimeout(10_000, () => {
      req.close(http2.constants.NGHTTP2_CANCEL);
      resolve({ status: 0, reason: "timeout" });
    });

    req.end(JSON.stringify(body));
  });
}

/**
 * Sends `payload` to a list of token rows, routing each to its APNs host.
 *
 * @param {Array<{ token: string, environment: "sandbox"|"production" }>} tokenRows
 * @param {object} payload  Full APNs body: { aps: {...}, type, matchId?, userId? }
 * @param {object} [options]
 * @param {string} [options.collapseId]  apns-collapse-id header value
 * @returns {Promise<{ sent: number, badTokens: string[] }>}
 *   badTokens = tokens APNs reported dead (410 Unregistered / BadDeviceToken) —
 *   the caller must delete those rows.
 */
export async function sendToTokens(tokenRows, payload, options = {}) {
  const extraHeaders = {};
  if (options.collapseId) extraHeaders["apns-collapse-id"] = options.collapseId;

  const byEnv = new Map();
  for (const row of tokenRows) {
    const env = row.environment === "sandbox" ? "sandbox" : "production";
    if (!byEnv.has(env)) byEnv.set(env, []);
    byEnv.get(env).push(row.token);
  }

  const jwt = apnsJwt();
  let sent = 0;
  const badTokens = [];

  for (const [env, tokens] of byEnv) {
    const session = http2.connect(HOSTS[env]);
    const sessionError = new Promise((resolve) => {
      session.on("error", (err) => resolve(err));
    });
    try {
      const results = await Promise.race([
        Promise.all(tokens.map((t) => sendOne(session, jwt, t, payload, extraHeaders))),
        sessionError.then((err) => {
          throw err;
        }),
      ]);
      results.forEach((result, i) => {
        if (result.status === 200) {
          sent += 1;
        } else if (result.status === 410 || result.reason === "BadDeviceToken") {
          badTokens.push(tokens[i]);
        } else {
          console.warn(
            `[apns] ${env} send failed status=${result.status} reason=${result.reason ?? "?"}`
          );
        }
      });
    } catch (err) {
      console.error(`[apns] ${env} session error: ${err?.code ?? err?.message ?? err}`);
    } finally {
      session.close();
    }
  }

  return { sent, badTokens };
}
