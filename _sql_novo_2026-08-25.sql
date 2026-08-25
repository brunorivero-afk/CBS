-- ============================================================
-- Rodar isso no SQL Editor do Supabase (idempotente).
-- Modelo oficial do NDA, cadastrável em Configurações.
-- ============================================================
alter table cbs_config add column if not exists nda_template_path text;
