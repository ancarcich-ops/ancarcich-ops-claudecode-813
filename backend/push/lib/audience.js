// Audience resolution + token loading (spec §5 general rules).
//
// ALL schema coupling for fanout lives in this file. The SQL below assumes
// the following tables — adjust names/columns here if sticks-golf differs:
//
//   match_players(id, match_id, user_id NULLABLE)
//   matches(id, group_id NULLABLE, tee_time timestamptz, status)
//   follows(follower_id, followee_id, state)   -- state 'accepted' | 'pending'
//   group_members(group_id, user_id)
//   push_tokens / push_prefs / push_events_sent (see migrations/001_push.sql)
//   push_round_alerts (see migrations/002_round_alerts.sql)

import { query } from "./db.js";

/** Maps a pref key (camelCase, as the app sends it) to its column. */
const PREF_COLUMNS = {
  roundStarts: "round_starts",
  birdiesAndBetter: "birdies_and_better",
  frontNineScores: "front_nine_scores",
  finalScores: "final_scores",
  followRequests: "follow_requests",
};

/**
 * Audience for round events (spec §5):
 * (accepted followers of each seated, account-linked player)
 * ∪ (users who share ANY group with a seated player — groupmates)
 * ∪ (members of the round's group, if any)
 * ∪ (users who turned alerts ON for this specific round — mode 'all')
 * − seated players − the actor − users who MUTED this round.
 *
 * The groupmate rule is relationship-based, not round-based: if you're in
 * a group with someone, you hear about every round they play — personal,
 * public, or attached to a different group.
 *
 * The per-round opt-in (push_round_alerts.mode = 'all') is what lets
 * someone follow one important match without following its players or
 * un-muting a whole group.
 *
 * @returns {Promise<string[]>} deduped recipient user ids
 */
export async function roundEventAudience(matchId, actorUserId) {
  const { rows } = await query(
    `
    WITH seated AS (
      SELECT user_id
      FROM match_players
      WHERE match_id = $1 AND user_id IS NOT NULL
    ),
    followers AS (
      SELECT f.follower_id AS user_id
      FROM follows f
      JOIN seated s ON s.user_id = f.followee_id
      WHERE f.state = 'accepted'
    ),
    -- Anyone sharing at least one group with a seated player, regardless of
    -- which group (if any) this round belongs to.
    groupmates AS (
      SELECT DISTINCT mine.user_id
      FROM group_members theirs
      JOIN seated s ON s.user_id = theirs.user_id
      JOIN group_members mine ON mine.group_id = theirs.group_id
    ),
    group_audience AS (
      SELECT gm.user_id
      FROM group_members gm
      JOIN matches m ON m.group_id = gm.group_id
      WHERE m.id = $1
    ),
    opted_in AS (
      SELECT user_id
      FROM push_round_alerts
      WHERE match_id = $1 AND mode = 'all'
    ),
    muted AS (
      SELECT user_id
      FROM push_round_alerts
      WHERE match_id = $1 AND mode = 'mute'
    )
    SELECT DISTINCT user_id
    FROM (
      SELECT user_id FROM followers
      UNION SELECT user_id FROM groupmates
      UNION SELECT user_id FROM group_audience
      UNION SELECT user_id FROM opted_in
    ) a
    WHERE user_id NOT IN (SELECT user_id FROM seated)
      AND user_id NOT IN (SELECT user_id FROM muted)
      AND user_id <> $2
    `,
    [matchId, actorUserId]
  );
  return rows.map((r) => r.user_id);
}

/**
 * Abandoned-round rule (spec §5): no pushes for rounds live > 24h past
 * tee time. Returns true when the match may still send pushes.
 */
export async function matchIsPushable(matchId) {
  const { rows } = await query(
    `
    SELECT 1
    FROM matches
    WHERE id = $1
      AND NOT (status = 'IN_PROGRESS' AND tee_time < now() - interval '24 hours')
    `,
    [matchId]
  );
  return rows.length > 0;
}

/**
 * Loads token rows for recipients who have the given pref enabled.
 * A missing push_prefs row counts as "everything on".
 *
 * When `matchId` is given, anyone who explicitly turned alerts ON for
 * that round (mode 'all') bypasses their category toggles — an explicit
 * per-round opt-in outranks the account-wide default.
 *
 * @param {string[]} userIds
 * @param {keyof typeof PREF_COLUMNS} prefKey
 * @param {string} [matchId] round context, for per-round overrides
 * @returns {Promise<Array<{ token: string, environment: string, user_id: string }>>}
 */
export async function tokensForUsers(userIds, prefKey, matchId) {
  const column = PREF_COLUMNS[prefKey];
  if (!column) throw new Error(`Unknown pref key: ${prefKey}`);
  if (userIds.length === 0) return [];

  if (!matchId) {
    const { rows } = await query(
      `
      SELECT t.token, t.environment, t.user_id
      FROM push_tokens t
      LEFT JOIN push_prefs p ON p.user_id = t.user_id
      WHERE t.user_id = ANY($1)
        AND COALESCE(p.${column}, true)
      `,
      [userIds]
    );
    return rows;
  }

  const { rows } = await query(
    `
    SELECT t.token, t.environment, t.user_id
    FROM push_tokens t
    LEFT JOIN push_prefs p ON p.user_id = t.user_id
    LEFT JOIN push_round_alerts a
           ON a.user_id = t.user_id AND a.match_id = $2
    WHERE t.user_id = ANY($1)
      AND a.mode IS DISTINCT FROM 'mute'
      AND (a.mode = 'all' OR COALESCE(p.${column}, true))
    `,
    [userIds, matchId]
  );
  return rows;
}

/**
 * The caller's alert override for one round: 'default' | 'all' | 'mute'.
 */
export async function roundAlertMode(matchId, userId) {
  const { rows } = await query(
    `SELECT mode FROM push_round_alerts WHERE match_id = $1 AND user_id = $2`,
    [matchId, userId]
  );
  return rows[0]?.mode ?? "default";
}

/**
 * Stores (or clears, for 'default') a per-round alert override.
 */
export async function setRoundAlertMode(matchId, userId, mode) {
  if (mode === "default") {
    await query(`DELETE FROM push_round_alerts WHERE match_id = $1 AND user_id = $2`, [
      matchId,
      userId,
    ]);
    return;
  }
  await query(
    `
    INSERT INTO push_round_alerts (match_id, user_id, mode, updated_at)
    VALUES ($1, $2, $3, now())
    ON CONFLICT (match_id, user_id) DO UPDATE SET
      mode = EXCLUDED.mode,
      updated_at = now()
    `,
    [matchId, userId, mode]
  );
}

/** Deletes token rows APNs reported dead (410 / BadDeviceToken). */
export async function deleteTokens(tokens) {
  if (tokens.length === 0) return;
  await query(`DELETE FROM push_tokens WHERE token = ANY($1)`, [tokens]);
}

/**
 * Fire-once guard: returns true exactly once per event key
 * (e.g. "start-<matchId>", "f9-<matchPlayerId>", "final-<matchId>").
 */
export async function markEventOnce(eventKey) {
  const { rowCount } = await query(
    `INSERT INTO push_events_sent (event_key) VALUES ($1)
     ON CONFLICT (event_key) DO NOTHING`,
    [eventKey]
  );
  return rowCount > 0;
}
