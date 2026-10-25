-- 016: upload de-duplication by content hash (GUARDRAILS 3.7 workstream E).
-- A re-uploaded identical clip returns the existing shot instead of running a second analysis (DEC-055 uploads).
-- Until this is applied the API still accepts uploads; dedupe is simply off (set_content_hash / find_upload_by_hash
-- degrade to no-ops when the column is absent), so applying it is safe and non-breaking.

alter table shots add column if not exists content_hash text;

-- one lookup per (user, hash) over standalone uploads
create index if not exists shots_user_content_hash_idx
    on shots (user_id, content_hash)
    where content_hash is not null;

comment on column shots.content_hash is
    'sha256 of the uploaded clip bytes; used to return an existing upload instead of re-analyzing a duplicate (DEC-055).';
