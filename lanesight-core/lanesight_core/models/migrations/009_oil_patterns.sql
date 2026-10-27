-- 009 Oil pattern library (DEC-052). Idempotent.
-- The oil_patterns table already exists (schema v1) with name/length_ft/volume_ml/ratio/source/sheet_url/
-- created_by/is_public and RLS from 004. This adds the provenance fields DEC-052 calls for and seeds the
-- two always-present builtin entries. The published-pattern importer + scheduled refresh is code
-- (lanesight_core, DV-02/later); SOURCE SELECTION AND TERMS ARE AN OPEN ITEM PENDING SHAYNE (DEC-052, §7).

alter table oil_patterns
  add column if not exists source_url text,
  add column if not exists fetched_at timestamptz;

-- Seeds: House shot and Unknown are always available. No fabricated length/volume — a generic house
-- shot and an unknown pattern have no single sourced value, so those stay null (DEC-026: no mock numbers).
insert into oil_patterns (name, source, is_public, created_by)
  select 'House shot', 'builtin', true, null
  where not exists (select 1 from oil_patterns where name = 'House shot' and created_by is null);
insert into oil_patterns (name, source, is_public, created_by)
  select 'Unknown', 'builtin', true, null
  where not exists (select 1 from oil_patterns where name = 'Unknown' and created_by is null);

-- Refresh-job design (for the importer built later):
--   1. Pull a published-pattern list from an approved source (name, length, volume, ratio, source_url).
--   2. Upsert by (name, source); set fetched_at = now(); never overwrite user-entered patterns
--      (created_by is not null) or the builtin House shot / Unknown rows.
--   3. Leave unpublished values null, never guessed. Record source + source_url for every row.
