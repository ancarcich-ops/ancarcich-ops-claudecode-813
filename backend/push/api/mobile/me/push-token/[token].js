// DELETE /api/mobile/me/push-token/:token — remove this device's token
// at sign-out (spec §3). Idempotent: 200 even when the row is already gone
// or belongs to nobody. Only deletes rows owned by the caller.

import { query } from "../../../../lib/db.js";
import { getUserIdFromRequest, sendError } from "../../../../lib/auth.js";

export default async function handler(req, res) {
  if (req.method !== "DELETE") {
    return sendError(res, 404, "Not found");
  }

  const userId = await getUserIdFromRequest(req);
  if (!userId) return sendError(res, 401, "Unauthorized");

  const token = String(req.query.token ?? "").toLowerCase();
  if (token) {
    await query(
      `DELETE FROM push_tokens WHERE token = $1 AND user_id = $2`,
      [token, userId]
    );
  }

  return res.status(200).json({ ok: true });
}
