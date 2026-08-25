-- ============================================================
-- Rodar isso no SQL Editor do Supabase (idempotente).
-- Novidade: CPF e "tamanho da equipe" (informado) no cadastro de Comissionado,
-- pra gerar o termo de NDA já preenchido e dar visibilidade de líder que administra rede própria.
-- ============================================================
alter table cbs_comissionados add column if not exists cpf text;
alter table cbs_comissionados add column if not exists tamanho_equipe_estimado integer;
