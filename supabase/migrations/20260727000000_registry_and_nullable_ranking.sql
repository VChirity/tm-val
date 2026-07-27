-- TM Val: ranking nullable, flags de exibição na home e tabela de registro (~top1000 nomes).
-- Não altera/apaga athlete_notes nem broadcast_notes.

CREATE EXTENSION IF NOT EXISTS "pg_trgm";

ALTER TABLE athletes ALTER COLUMN ranking DROP NOT NULL;
ALTER TABLE athletes ADD COLUMN IF NOT EXISTS listed_in_home BOOLEAN NOT NULL DEFAULT true;
ALTER TABLE athletes ADD COLUMN IF NOT EXISTS country_code TEXT;
ALTER TABLE athletes ADD COLUMN IF NOT EXISTS profile_hydrated BOOLEAN NOT NULL DEFAULT true;

CREATE INDEX IF NOT EXISTS athletes_listed_in_home_idx ON athletes (listed_in_home);

CREATE TABLE IF NOT EXISTS player_registry (
    ittf_id TEXT PRIMARY KEY,
    name TEXT NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female')),
    country_code TEXT,
    ranking INTEGER,
    ranking_points INTEGER,
    photo_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS player_registry_name_idx
    ON player_registry USING gin (name gin_trgm_ops);

CREATE INDEX IF NOT EXISTS player_registry_ranking_idx
    ON player_registry (gender, ranking ASC);

ALTER TABLE player_registry ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "player_registry_auth_all" ON player_registry;
CREATE POLICY "player_registry_auth_all"
    ON player_registry FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);
