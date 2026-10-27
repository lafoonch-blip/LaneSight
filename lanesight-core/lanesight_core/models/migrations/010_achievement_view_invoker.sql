-- 010 Fix achievement_definition client exposure (clears advisor ERROR security_definer_view). Idempotent.
--
-- OWNER-ONLY POSTURE (DEC-046) — intentional: the rule/engine tables (benchmark_reference, style_template,
-- style_template_metric, drill, form_rule, engine_config, score_formula_version, engine_event) have RLS
-- ENABLED with NO policy and NO client grant. That is a deliberate deny-all to every client role; the
-- advisor's INFO 'rls_enabled_no_policy' on those tables is EXPECTED, not a defect. Do not "fix" it by
-- adding a client policy.
--
-- achievement_definition is the one rule table clients may partially read — the user-facing columns only,
-- never `params`, never draft/retired rows. Instead of a SECURITY DEFINER view (which the linter rejects,
-- lint 0010), we grant COLUMN-LEVEL select + an RLS select policy, and make the view security_invoker.
-- The column grant is explicit on purpose: any column added to achievement_definition later (including a
-- future secret) stays hidden from clients unless it is deliberately added to this grant.

-- belt-and-suspenders: ensure no table-level SELECT lingers for either client role (007 revoked all).
revoke select on achievement_definition from anon, authenticated;

-- column-level select for authenticated ONLY (never anon); `params` deliberately excluded.
grant select (id, category, name, description, status, inactive_reason, badge_asset)
  on achievement_definition to authenticated;

-- rows limited to the launch-visible catalog (hides draft/retired).
drop policy if exists client_read_active on achievement_definition;
create policy client_read_active on achievement_definition for select to authenticated
  using (status in ('active','coming_later'));

-- recreate the public view WITHOUT security definer; now resolvable via the column grant + policy above.
drop view if exists achievement_definition_public;
create view achievement_definition_public with (security_invoker = true) as
  select id, category, name, description, status, inactive_reason, badge_asset
  from achievement_definition
  where status in ('active','coming_later');
grant select on achievement_definition_public to authenticated;
