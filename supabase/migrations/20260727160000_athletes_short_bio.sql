-- Bio curta (lead Wikipedia) para ficha do atleta.
ALTER TABLE athletes ADD COLUMN IF NOT EXISTS short_bio TEXT;
