-- Per-round alert overrides (slice 72).
--
-- 'all'  → this user gets EVERY round event for this match, ignoring
--          their account-wide category toggles and regardless of whether
--          they follow a seated player or share the round's group.
-- 'mute' → this user gets NOTHING for this match, even from players they
--          follow.
-- No row  → 'default': the normal follow/group + category rules apply.

CREATE TABLE IF NOT EXISTS push_round_alerts (
  match_id   text NOT NULL,               -- fk -> matches.id
  user_id    text NOT NULL,               -- fk -> users.id
  mode       text NOT NULL CHECK (mode IN ('all', 'mute')),
  updated_at timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (match_id, user_id)
);

CREATE INDEX IF NOT EXISTS push_round_alerts_match_mode_idx
  ON push_round_alerts (match_id, mode);
