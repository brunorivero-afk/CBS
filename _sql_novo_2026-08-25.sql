-- ============================================================
-- Rodar isso no SQL Editor do Supabase (idempotente).
-- Checklist de onboarding por comissionado.
-- ============================================================
alter table cbs_comissionados add column if not exists onboarding_script boolean not null default false;
alter table cbs_comissionados add column if not exists onboarding_duplicidade boolean not null default false;
