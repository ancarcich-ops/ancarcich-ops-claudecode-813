// POST /api/mobile/me/push-token — upsert this device's APNs token (spec §3).
// Body: { token, platform: "ios", environment: "sandbox"|"production", appVersion? }
//
// A token moving to a different user on upsert is normal (shared device,
// account switch) — always reassign.

import { query } from "../../../lib/db.js";
import { getUserIdFromRequest, sendError } from "../../../lib/auth.js";

export default async function handler(req, res) {
  if (req.method !== "POST") {
    return sendError(res, 404, "Not found");
  }

  const userId = await getUserIdFromRequest(req);
  if (!userId) return sendError(res, 401, "Unauthorized");

  const { token, platform, environment, appVersion } = req.body ?? {};

  if (typeof token !== "string" || !/^[0-9a-fA-F]{16,}$/.test(token)) {
    return sendError(res, 400, "Invalid device token");
  }
  if (platform !== "ios") {
    return sendError(res, 400, "Unsupported platform");
  }
  if (environment !== "sandbox" && environment !== "production") {
    return sendError(res, 400, "Invalid environment");
  }

  await query(
    `
    INSERT INTO push_tokens (token, user_id, platform, environment, app_version, updated_at)
    VALUES ($1, $2, $3, $4, $5, now())
    ON CONFLICT (token) DO UPDATE SET
      user_id = EXCLUDED.user_id,
      platform = EXCLUDED.platform,
      environment = EXCLUDED.environment,
      app_version = EXCLUDED.app_version,
      updated_at = now()
    `,
    [token.toLowerCase(), userId, platform, environment, typeof appVersion === "string" ? appVersion : null]
  );

  return res.status(200).json({ ok: true });
}
