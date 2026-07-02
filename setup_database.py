#!/usr/bin/env python3
"""Cria as tabelas do TM Val no Supabase via connection string PostgreSQL."""

from __future__ import annotations

import os
import sys
from pathlib import Path

import psycopg2
from dotenv import load_dotenv

ROOT_DIR = Path(__file__).resolve().parent
ENV_PATH = ROOT_DIR / ".env"

SCHEMA_SQL = """
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

CREATE TABLE IF NOT EXISTS athletes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    gender TEXT NOT NULL CHECK (gender IN ('male', 'female')),
    ranking INTEGER NOT NULL,
    ranking_points INTEGER,
    age INTEGER,
    height DOUBLE PRECISION,
    hand TEXT,
    championships_won TEXT[] DEFAULT '{}',
    photo_url TEXT,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT athletes_name_gender_key UNIQUE (name, gender)
);

CREATE INDEX IF NOT EXISTS athletes_gender_ranking_idx
    ON athletes (gender, ranking ASC);

CREATE TABLE IF NOT EXISTS athlete_notes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    athlete_id UUID NOT NULL REFERENCES athletes(id) ON DELETE CASCADE,
    content TEXT NOT NULL DEFAULT '',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX IF NOT EXISTS athlete_notes_athlete_id_uidx
    ON athlete_notes (athlete_id);

CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS athletes_set_updated_at ON athletes;
CREATE TRIGGER athletes_set_updated_at
    BEFORE UPDATE ON athletes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

DROP TRIGGER IF EXISTS athlete_notes_set_updated_at ON athlete_notes;
CREATE TRIGGER athlete_notes_set_updated_at
    BEFORE UPDATE ON athlete_notes
    FOR EACH ROW
    EXECUTE FUNCTION set_updated_at();

ALTER TABLE athletes ENABLE ROW LEVEL SECURITY;
ALTER TABLE athlete_notes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "athletes_public_read" ON athletes;
DROP POLICY IF EXISTS "athletes_public_write" ON athletes;
DROP POLICY IF EXISTS "athletes_public_update" ON athletes;

CREATE POLICY "athletes_auth_select"
    ON athletes FOR SELECT
    TO authenticated
    USING (true);

CREATE POLICY "athletes_auth_insert"
    ON athletes FOR INSERT
    TO authenticated
    WITH CHECK (true);

CREATE POLICY "athletes_auth_update"
    ON athletes FOR UPDATE
    TO authenticated
    USING (true)
    WITH CHECK (true);

DROP POLICY IF EXISTS "athlete_notes_public_all" ON athlete_notes;
CREATE POLICY "athlete_notes_auth_all"
    ON athlete_notes FOR ALL
    TO authenticated
    USING (true)
    WITH CHECK (true);
"""


def ensure_env_file() -> None:
    if ENV_PATH.exists():
        return

    example = ROOT_DIR / ".env.example"
    if example.exists():
        ENV_PATH.write_text(example.read_text(encoding="utf-8"), encoding="utf-8")
        print(f"Arquivo {ENV_PATH.name} criado a partir de .env.example.")
    else:
        ENV_PATH.write_text("DATABASE_URL=\n", encoding="utf-8")

    print(
        "\nConfigure DATABASE_URL no arquivo .env com a connection string do Supabase "
        "e execute este script novamente.\n"
    )
    sys.exit(1)


def main() -> None:
    ensure_env_file()
    load_dotenv(ENV_PATH)

    database_url = os.getenv("DATABASE_URL", "").strip()
    if not database_url:
        print("Erro: DATABASE_URL não definida no arquivo .env")
        sys.exit(1)

    print("Conectando ao PostgreSQL do Supabase...")
    try:
        with psycopg2.connect(database_url) as conn:
            conn.autocommit = True
            with conn.cursor() as cursor:
                cursor.execute(SCHEMA_SQL)
                cursor.execute(
                    "ALTER TABLE athletes ADD COLUMN IF NOT EXISTS ranking_points INTEGER;"
                )
                cursor.execute(
                    """
                    SELECT table_name
                    FROM information_schema.tables
                    WHERE table_schema = 'public'
                      AND table_name IN ('athletes', 'athlete_notes')
                    ORDER BY table_name;
                    """
                )
                tables = [row[0] for row in cursor.fetchall()]
    except psycopg2.Error as exc:
        print(f"Erro ao executar o setup: {exc}")
        sys.exit(1)

    print("Setup concluído com sucesso.")
    print("Tabelas disponíveis:", ", ".join(tables))


if __name__ == "__main__":
    main()
