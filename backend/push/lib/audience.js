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
 * ∪ (members of the round's group, if any)
 * − seated players − the actor.
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
    group_audience AS (
      SELECT gm.user_id
      FROM group_members gm
      JOIN matches m ON m.group_id = gm.group_id
      WHERE m.id = $1
    )
    SELECT DISTINCT user_id
    FROM (SELECT user_id FROM followers UNION SELECT user_id FROM group_audience) a
    WHERE user_id NOT IN (SELECT user_id FROM seated)
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
 * @param {string[]} userIds
 * @param {keyof typeof PREF_COLUMNS} prefKey
 * @returns {Promise<Array<{ token: string, environment: string, user_id: string }>>}
 */
export async function tokensForUsers(userIds, prefKey) {
  const column = PREF_COLUMNS[prefKey];
  if (!column) throw new Error(`Unknown pref key: ${prefKey}`);
  if (userIds.length === 0) return [];

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
