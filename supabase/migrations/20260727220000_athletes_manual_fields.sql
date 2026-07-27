-- Campos da ficha técnica editados manualmente não devem ser sobrescritos pelo sync WTT.
ALTER TABLE athletes ADD COLUMN IF NOT EXISTS manual_fields jsonb NOT NULL DEFAULT '{}'::jsonb;
COMMENT ON COLUMN athletes.manual_fields IS
  'Map of profile fields edited manually; sync must not overwrite keys set to true.';
