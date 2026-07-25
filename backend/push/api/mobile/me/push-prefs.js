// GET  /api/mobile/me/push-prefs — the caller's category toggles (spec §3).
// POST /api/mobile/me/push-prefs — replace with the full prefs object.
//
// All prefs default true; a missing row means "everything on".

import { query } from "../../../lib/db.js";
import { getUserIdFromRequest, sendError } from "../../../lib/auth.js";

const PREF_KEYS = [
  ["roundStarts", "round_starts"],
  ["birdiesAndBetter", "birdies_and_better"],
  ["frontNineScores", "front_nine_scores"],
  ["finalScores", "final_scores"],
  ["followRequests", "follow_requests"],
];

export default async function handler(req, res) {
  const userId = await getUserIdFromRequest(req);
  if (!userId) return sendError(res, 401, "Unauthorized");

  if (req.method === "GET") {
    const { rows } = await query(
      `SELECT round_starts, birdies_and_better, front_nine_scores,
              final_scores, follow_requests
       FROM push_prefs WHERE user_id = $1`,
      [userId]
    );
    const row = rows[0];
    const prefs = {};
    for (const [jsonKey, column] of PREF_KEYS) {
      prefs[jsonKey] = row ? Boolean(row[column]) : true;
    }
    return res.status(200).json({ prefs });
  }

  if (req.method === "POST") {
    const body = req.body ?? {};
    // The app always sends the full object; treat missing keys as true
    // (their default) so a partial body can never silently disable a category.
    const values = PREF_KEYS.map(([jsonKey]) =>
      typeof body[jsonKey] === "boolean" ? body[jsonKey] : true
    );

    await query(
      `
      INSERT INTO push_prefs
        (user_id, round_starts, birdies_and_better, front_nine_scores,
         final_scores, follow_requests, updated_at)
      VALUES ($1, $2, $3, $4, $5, $6, now())
      ON CONFLICT (user_id) DO UPDATE SET
        round_starts = EXCLUDED.round_starts,
        birdies_and_better = EXCLUDED.birdies_and_better,
        front_nine_scores = EXCLUDED.front_nine_scores,
        final_scores = EXCLUDED.final_scores,
        follow_requests = EXCLUDED.follow_requests,
        updated_at = now()
      `,
      [userId, ...values]
    );
    return res.status(200).json({ ok: true });
  }

  return sendError(res, 404, "Not found");
}
