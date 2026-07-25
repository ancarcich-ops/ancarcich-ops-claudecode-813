// Event senders — one function per notification category (spec §5).
//
// Call these from the existing route handlers AFTER responding to the
// client, via waitUntil (see README). Each sender:
//   1. applies the fire-once guard where required,
//   2. resolves the audience and filters by pref,
//   3. sends via APNs and prunes dead tokens.
// Every sender is fail-soft: it logs and never throws into the request path.
//
// Callers pass display strings (player/course names) they already have in
// scope — these functions do not query match details themselves.

import { sendToTokens } from "./apns.js";
import {
  roundEventAudience,
  matchIsPushable,
  tokensForUsers,
  deleteTokens,
  markEventOnce,
} from "./audience.js";

/** Formats a to-par delta: +3 / E / -2. */
function formatToPar(toPar) {
  if (toPar === 0) return "E";
  return toPar > 0 ? `+${toPar}` : `${toPar}`;
}

/** Builds the payload contract from spec §4. */
function buildPayload({ title, body, matchId, type, userId, badge, threadId }) {
  const aps = { alert: { title, body }, sound: "default" };
  if (threadId) aps["thread-id"] = threadId;
  if (typeof badge === "number") aps.badge = badge;
  const payload = { aps, type };
  if (matchId) payload.matchId = matchId;
  if (userId) payload.userId = userId;
  return payload;
}

/**
 * Shared fanout tail: load tokens, send, prune dead rows.
 *
 * `payload.matchId` (when present) scopes the token query to that round
 * so per-round overrides apply — an explicit "alerts on for this round"
 * bypasses the recipient's category toggles, a mute drops them.
 */
async function deliver(userIds, prefKey, payload, collapseId) {
  const tokenRows = await tokensForUsers(userIds, prefKey, payload.matchId);
  if (tokenRows.length === 0) return;
  const { sent, badTokens } = await sendToTokens(tokenRows, payload, { collapseId });
  if (badTokens.length > 0) await deleteTokens(badTokens);
  console.log(
    `[push] ${payload.type} sent=${sent} pruned=${badTokens.length} audience=${userIds.length}`
  );
}

/** Round-event boilerplate: pushable check + audience resolution. */
async function roundAudienceOrNull(matchId, actorUserId) {
  if (!(await matchIsPushable(matchId))) return null;
  const audience = await roundEventAudience(matchId, actorUserId);
  return audience.length > 0 ? audience : null;
}

/**
 * round_start — call when the first score of a match is posted
 * (status flips to IN_PROGRESS). Safe to call on every score post;
 * the fire-once guard makes it a no-op after the first send.
 *
 * @param {object} p
 * @param {string} p.matchId
 * @param {string} p.actorUserId    the player who posted the score
 * @param {string} p.playerName     e.g. "Tj"
 * @param {string} p.courseName     e.g. "Rustic Canyon"
 * @param {number} p.seatCount      total seats in the round
 */
export async function notifyRoundStart({ matchId, actorUserId, playerName, courseName, seatCount }) {
  try {
    if (!(await markEventOnce(`start-${matchId}`))) return;
    const audience = await roundAudienceOrNull(matchId, actorUserId);
    if (!audience) return;

    const others = seatCount - 1;
    const body =
      others > 0
        ? `${playerName} teed off at ${courseName} with ${others} other${others === 1 ? "" : "s"}`
        : `${playerName} teed off at ${courseName}`;

    await deliver(
      audience,
      "roundStarts",
      buildPayload({
        title: "Round starting",
        body,
        matchId,
        type: "round_start",
        userId: actorUserId,
        threadId: matchId,
      }),
      `start-${matchId}`
    );
  } catch (err) {
    console.error(`[push] round_start failed for ${matchId}:`, err);
  }
}

/**
 * score_highlight — call from POST /matches/:id/score when
 * strokes <= par - 1. If a correction later drops the score below
 * birdie, simply don't call this (spec: accept the stale alert).
 *
 * @param {object} p
 * @param {string} p.matchId
 * @param {string} p.matchPlayerId  seat that scored (for the collapse id)
 * @param {string} p.actorUserId    the player who posted the score
 * @param {string} p.playerName
 * @param {string} p.courseName
 * @param {number} p.hole           1-18
 * @param {number} p.par
 * @param {number} p.strokes
 */
export async function notifyScoreHighlight({
  matchId,
  matchPlayerId,
  actorUserId,
  playerName,
  courseName,
  hole,
  par,
  strokes,
}) {
  try {
    const diff = par - strokes;
    let title;
    let verb;
    if (strokes === 1) {
      title = "ACE 🎯";
      verb = "aced";
    } else if (diff === 1) {
      title = "Birdie 🐦";
      verb = "birdied";
    } else if (diff === 2) {
      title = "Eagle";
      verb = "eagled";
    } else if (diff >= 3) {
      title = "Albatross";
      verb = "made albatross on";
    } else {
      return; // not birdie-or-better — nothing to send
    }

    const audience = await roundAudienceOrNull(matchId, actorUserId);
    if (!audience) return;

    await deliver(
      audience,
      "birdiesAndBetter",
      buildPayload({
        title,
        body: `${playerName} ${verb} hole ${hole} at ${courseName}`,
        matchId,
        type: "score_highlight",
        userId: actorUserId,
        threadId: matchId,
      }),
      // A corrected score replaces the earlier alert instead of double-notifying.
      `hl-${matchPlayerId}-${hole}`
    );
  } catch (err) {
    console.error(`[push] score_highlight failed for ${matchId}:`, err);
  }
}

/**
 * front_nine — call when a player's 9th front-nine hole score lands
 * (holes 1–9 all have strokes). Fire-once per match player is handled here.
 *
 * @param {object} p
 * @param {string} p.matchId
 * @param {string} p.matchPlayerId
 * @param {string} p.actorUserId
 * @param {string} p.playerName
 * @param {string} p.courseName
 * @param {number} p.frontTotal     strokes for holes 1-9, e.g. 39
 * @param {number} p.frontToPar     e.g. 3 → "(+3)", 0 → "(E)"
 */
export async function notifyFrontNine({
  matchId,
  matchPlayerId,
  actorUserId,
  playerName,
  courseName,
  frontTotal,
  frontToPar,
}) {
  try {
    if (!(await markEventOnce(`f9-${matchPlayerId}`))) return;
    const audience = await roundAudienceOrNull(matchId, actorUserId);
    if (!audience) return;

    await deliver(
      audience,
      "frontNineScores",
      buildPayload({
        title: "Made the turn",
        body: `${playerName} out in ${frontTotal} (${formatToPar(frontToPar)}) at ${courseName}`,
        matchId,
        type: "front_nine",
        userId: actorUserId,
        threadId: matchId,
      }),
      `f9-${matchPlayerId}`
    );
  } catch (err) {
    console.error(`[push] front_nine failed for ${matchId}:`, err);
  }
}

/**
 * round_final — call from POST /matches/:id/complete. Fire-once guard
 * keeps the (already idempotent) endpoint from double-sending.
 *
 * @param {object} p
 * @param {string} p.matchId
 * @param {string} p.actorUserId    whoever completed the round
 * @param {string} p.courseName
 * @param {Array<{ name: string, total: number, toPar: number }>} p.results
 *   one entry per seat, best score first
 */
export async function notifyRoundFinal({ matchId, actorUserId, courseName, results }) {
  try {
    if (!(await markEventOnce(`final-${matchId}`))) return;
    if (results.length === 0) return;
    const audience = await roundAudienceOrNull(matchId, actorUserId);
    if (!audience) return;

    let body;
    if (results.length === 1) {
      const r = results[0];
      body = `${r.name} shot ${r.total} (${formatToPar(r.toPar)}) at ${courseName}`;
    } else {
      const shown = results.slice(0, 3).map((r) => `${r.name} ${r.total}`);
      const extra = results.length - 3;
      body = `${courseName} final: ${shown.join(", ")}${extra > 0 ? ` +${extra} more` : ""}`;
    }

    await deliver(
      audience,
      "finalScores",
      buildPayload({
        title: "Final scores",
        body,
        matchId,
        type: "round_final",
        userId: actorUserId,
        threadId: matchId,
      }),
      `final-${matchId}`
    );
  } catch (err) {
    console.error(`[push] round_final failed for ${matchId}:`, err);
  }
}

/**
 * follow_request — call from POST /follows action=request when the
 * target does NOT auto-accept.
 *
 * @param {object} p
 * @param {string} p.targetUserId       recipient
 * @param {string} p.requesterUserId    actor (goes into payload userId)
 * @param {string} p.requesterUsername  without the @
 * @param {number} [p.pendingCount]     target's pending request count (badge)
 */
export async function notifyFollowRequest({
  targetUserId,
  requesterUserId,
  requesterUsername,
  pendingCount,
}) {
  try {
    await deliver(
      [targetUserId],
      "followRequests",
      buildPayload({
        title: "Follow request",
        body: `@${requesterUsername} wants to follow you`,
        type: "follow_request",
        userId: requesterUserId,
        badge: typeof pendingCount === "number" ? pendingCount : undefined,
      })
    );
  } catch (err) {
    console.error(`[push] follow_request failed for ${targetUserId}:`, err);
  }
}

/**
 * follow_accept — call from POST /follows action=accept (including
 * auto-accepted requests).
 *
 * @param {object} p
 * @param {string} p.requesterUserId    recipient (the original requester)
 * @param {string} p.accepterUserId     actor
 * @param {string} p.accepterUsername   without the @
 */
export async function notifyFollowAccept({ requesterUserId, accepterUserId, accepterUsername }) {
  try {
    await deliver(
      [requesterUserId],
      "followRequests",
      buildPayload({
        title: "Request accepted",
        body: `@${accepterUsername} accepted your follow request`,
        type: "follow_accept",
        userId: accepterUserId,
      })
    );
  } catch (err) {
    console.error(`[push] follow_accept failed for ${requesterUserId}:`, err);
  }
}
