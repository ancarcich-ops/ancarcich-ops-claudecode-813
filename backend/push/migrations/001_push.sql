-- Push notification storage (spec: docs/push-notifications-backend-handoff.md §2)

CREATE TABLE IF NOT EXISTS push_tokens (
  token       text PRIMARY KEY,             -- hex APNs device token
  user_id     text NOT NULL,                -- fk -> users.id (match your users pk type)
  platform    text NOT NULL DEFAULT 'ios',
  environment text NOT NULL DEFAULT 'production'
              CHECK (environment IN ('sandbox', 'production')),
  app_version text,
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS push_tokens_user_id_idx ON push_tokens (user_id);

-- All prefs default TRUE; a missing row means "everything on".
CREATE TABLE IF NOT EXISTS push_prefs (
  user_id            text PRIMARY KEY,      -- fk -> users.id
  round_starts       boolean NOT NULL DEFAULT true,
  birdies_and_better boolean NOT NULL DEFAULT true,
  front_nine_scores  boolean NOT NULL DEFAULT true,
  final_scores       boolean NOT NULL DEFAULT true,
  follow_requests    boolean NOT NULL DEFAULT true,
  updated_at         timestamptz NOT NULL DEFAULT now()
);

-- Idempotency guard for fire-once events (round_start, front_nine, round_final).
CREATE TABLE IF NOT EXISTS push_events_sent (
  event_key text PRIMARY KEY,
  sent_at   timestamptz NOT NULL DEFAULT now()
);
