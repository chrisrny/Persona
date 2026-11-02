-- Persona database schema
-- Executed automatically by the Postgres container on first start
-- (only when the data volume is empty).

CREATE EXTENSION IF NOT EXISTS pgcrypto; -- gen_random_uuid(), crypt(), gen_salt()

-- ---------------------------------------------------------------------------
-- Topics: closed taxonomy shared by users (interests) and news (category)
-- ---------------------------------------------------------------------------
CREATE TABLE topics (
    slug  TEXT PRIMARY KEY CHECK (slug ~ '^[a-z][a-z0-9_]*$'),
    label TEXT NOT NULL
);

INSERT INTO topics (slug, label) VALUES
    ('tech',        'Technology'),
    ('ai',          'Artificial Intelligence'),
    ('science',     'Science'),
    ('economy',     'Economy & Business'),
    ('sport',       'Sport'),
    ('culture',     'Culture & Entertainment'),
    ('health',      'Health'),
    ('environment', 'Environment & Climate'),
    ('world',       'World News');

-- ---------------------------------------------------------------------------
-- Users
-- Only what the product needs is stored (GDPR data minimisation).
-- Passwords are hashed with bcrypt via pgcrypto:
--   store : crypt($password, gen_salt('bf', 10))
--   verify: password_hash = crypt($password, password_hash)
-- ---------------------------------------------------------------------------
CREATE TABLE users (
    id                    UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    username              TEXT NOT NULL CHECK (username ~ '^[A-Za-z0-9_]{3,32}$'),
    password_hash         TEXT NOT NULL,
    email                 TEXT CHECK (email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
    keywords              TEXT[] NOT NULL DEFAULT '{}',
    send_time             TIME,                                   -- HH:MM in the user's timezone
    timezone              TEXT NOT NULL DEFAULT 'Europe/Paris',   -- IANA name
    active                BOOLEAN NOT NULL DEFAULT TRUE,          -- FALSE = newsletter paused / unsubscribed
    role                  TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('user', 'admin')),
    consent_at            TIMESTAMPTZ NOT NULL,                   -- explicit GDPR consent at sign-up
    last_sent_at          TIMESTAMPTZ,                            -- prevents double sending
    failed_login_attempts INTEGER NOT NULL DEFAULT 0,
    locked_until          TIMESTAMPTZ,                            -- brute-force protection
    created_at            TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at            TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- Case-insensitive unique username
CREATE UNIQUE INDEX users_username_lower_idx ON users (lower(username));

CREATE TABLE user_topics (
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    topic_slug TEXT NOT NULL REFERENCES topics (slug),
    PRIMARY KEY (user_id, topic_slug)
);

-- ---------------------------------------------------------------------------
-- Sessions: links a Chat Trigger sessionId to an authenticated user
-- ---------------------------------------------------------------------------
CREATE TABLE sessions (
    session_id TEXT PRIMARY KEY,
    user_id    UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    expires_at TIMESTAMPTZ NOT NULL
);

CREATE INDEX sessions_user_id_idx ON sessions (user_id);

-- ---------------------------------------------------------------------------
-- News fetched from RSS sources
-- ---------------------------------------------------------------------------
CREATE TABLE news (
    id           BIGSERIAL PRIMARY KEY,
    url          TEXT NOT NULL UNIQUE,              -- deduplication key
    title        TEXT NOT NULL,
    description  TEXT,
    source       TEXT NOT NULL,
    topic_slug   TEXT NOT NULL REFERENCES topics (slug),
    published_at TIMESTAMPTZ,
    fetched_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX news_topic_published_idx ON news (topic_slug, published_at DESC);

-- ---------------------------------------------------------------------------
-- Sent newsletters and the news they contained
-- ---------------------------------------------------------------------------
CREATE TABLE newsletters (
    id      BIGSERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    sent_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX newsletters_user_id_idx ON newsletters (user_id, sent_at DESC);

CREATE TABLE newsletter_items (
    newsletter_id BIGINT NOT NULL REFERENCES newsletters (id) ON DELETE CASCADE,
    news_id       BIGINT NOT NULL REFERENCES news (id) ON DELETE CASCADE,
    PRIMARY KEY (newsletter_id, news_id)
);

CREATE INDEX newsletter_items_news_id_idx ON newsletter_items (news_id);

-- ---------------------------------------------------------------------------
-- Keep users.updated_at current
-- ---------------------------------------------------------------------------
CREATE FUNCTION set_updated_at() RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER users_set_updated_at
    BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
