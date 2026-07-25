// Bearer auth — wire this to the SAME session lookup the other
// /api/mobile routes use so tokens stay interchangeable.
//
// The default implementation assumes a `sessions` table
// (token → user_id). Replace the body of `getUserIdFromRequest` with
// your existing helper if the backend already has one.

import { query } from "./db.js";

/**
 * Resolves the authenticated user id from the Authorization header.
 * @param {import("http").IncomingMessage} req
 * @returns {Promise<string|null>} user id, or null when unauthenticated
 */
export async function getUserIdFromRequest(req) {
  const header = req.headers.authorization ?? "";
  const match = /^Bearer\s+(.+)$/i.exec(header);
  if (!match) return null;
  const token = match[1].trim();
  if (!token) return null;

  // ADAPT: swap for your existing session/JWT verification.
  const { rows } = await query(
    `SELECT user_id FROM sessions WHERE token = $1 LIMIT 1`,
    [token]
  );
  return rows[0]?.user_id ?? null;
}

/** Writes the standard { error } JSON body used by all /api/mobile routes. */
export function sendError(res, status, message) {
  res.status(status).json({ error: message });
}
