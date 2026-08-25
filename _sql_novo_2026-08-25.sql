-- ============================================================
-- Rodar isso no SQL Editor do Supabase (idempotente).
-- CNPJ/razão social no comissionado (pra comissionado pessoa jurídica, tipo empresa
-- parceira de intermediação) + remoção do campo "tamanho da equipe" (não será mais usado).
-- ============================================================
alter table cbs_comissionados add column if not exists cnpj text;
alter table cbs_comissionados add column if not exists razao_social text;
alter table cbs_comissionados drop column if exists tamanho_equipe_estimado;
