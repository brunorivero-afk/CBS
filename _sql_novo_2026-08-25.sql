-- ============================================================
-- Rodar isso no SQL Editor do Supabase (idempotente).
-- Razão social no cadastro de Negócio (distinto do nome fantasia), pra ter os dados
-- prontos quando precisar enviar cliente pra CorpLink.
-- ============================================================
alter table cbs_negocios add column if not exists razao_social text;
