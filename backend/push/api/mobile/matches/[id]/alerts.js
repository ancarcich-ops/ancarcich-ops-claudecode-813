// GET  /api/mobile/matches/:id/alerts — the caller's per-round alert override.
// POST /api/mobile/matches/:id/alerts — set it.
//
// Body: { "mode": "default" | "all" | "mute" }
//   all    → every round event for this match, ignoring category toggles
//            and the follow/group relationship
//   mute   → nothing for this match
//   default→ clears the override
//
// Any authenticated user who can SEE the round may set an override; the
// visibility check mirrors GET /matches/:id (public round, shared group,
// or seated/creator). Adjust the `canView` SQL if sticks-golf's
// visibility rules differ.

import { query } from "../../../../lib/db.js";
import { getUserIdFromRequest, sendError } from "../../../../lib/auth.js";
import { roundAlertMode, setRoundAlertMode } from "../../../../lib/audience.js";

const MODES = new Set(["default", "all", "mute"]);

/** True when `userId` is allowed to see this match at all. */
async function canView(matchId, userId) {
  const { rows } = await query(
    `
    SELECT 1
    FROM matches m
    WHERE m.id = $1
      AND (
        m.group_id IS NULL
        OR EXISTS (
          SELECT 1 FROM group_members gm
          WHERE gm.group_id = m.group_id AND gm.user_id = $2
        )
        OR EXISTS (
          SELECT 1 FROM match_players mp
          WHERE mp.match_id = m.id AND mp.user_id = $2
        )
      )
    LIMIT 1
    `,
    [matchId, userId]
  );
  return rows.length > 0;
}

export default async function handler(req, res) {
  const userId = await getUserIdFromRequest(req);
  if (!userId) return sendError(res, 401, "Unauthorized");

  const matchId = req.query?.id;
  if (!matchId) return sendError(res, 400, "Missing match id");

  if (!(await canView(matchId, userId))) {
    return sendError(res, 404, "Round not found");
  }

  if (req.method === "GET") {
    const mode = await roundAlertMode(matchId, userId);
    return res.status(200).json({ mode });
  }

  if (req.method === "POST") {
    const mode = req.body?.mode;
    if (typeof mode !== "string" || !MODES.has(mode)) {
      return sendError(res, 400, "mode must be 'default', 'all', or 'mute'");
    }
    await setRoundAlertMode(matchId, userId, mode);
    return res.status(200).json({ ok: true, mode });
  }

  return sendError(res, 404, "Not found");
}
