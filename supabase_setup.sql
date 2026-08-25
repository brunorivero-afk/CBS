-- CBS — setup Supabase
-- Rodar no SQL Editor do projeto pxcqyzbgfbwwkazmonzx (mesmo projeto do BIG GTD / Finanças Casa / Agenda Renata)
-- Todas as tabelas prefixadas "cbs_" pra ficar isolado dos outros apps no mesmo projeto.
--
-- Este arquivo é IDEMPOTENTE (pode rodar de novo sem quebrar nada — usa "if not exists"/"create or replace"/"on conflict").

-- ============================================================
-- 1. USUÁRIOS AUTORIZADOS (allowlist + perfil de cada um)
-- ============================================================
create table if not exists cbs_usuarios (
  email text primary key,
  nome text not null,
  posicao text not null check (posicao in ('Sócio','Comercial','Operacional')),
  lucro_pct numeric(6,2), -- % desse sócio no Lucro Sócio (opcional). Se não somar 100% entre os sócios, o sistema usa divisão igual.
  comissionado_id bigint, -- pra Comercial: liga esse login ao próprio cadastro em cbs_comissionados (usado pelo RLS pra restringir o que ele vê)
  created_at timestamptz default now()
);
alter table cbs_usuarios add column if not exists lucro_pct numeric(6,2);
alter table cbs_usuarios add column if not exists comissionado_id bigint;
alter table cbs_usuarios add column if not exists apelido text;
do $$ begin
  alter table cbs_usuarios add constraint cbs_usuarios_apelido_key unique (apelido);
exception when duplicate_object then null; end $$;

-- resolve apelido -> e-mail pra login curto. security definer + grant pro anon porque isso roda
-- ANTES de autenticar (não dá pra depender de RLS de cbs_usuarios, que exige estar logado).
-- Só devolve o e-mail (nada mais da tabela) e só quando existe o apelido — não dá pra enumerar usuários por aqui.
create or replace function cbs_email_by_apelido(p_apelido text)
returns text language sql security definer stable as $$
  select email from cbs_usuarios where apelido = lower(p_apelido) limit 1;
$$;
grant execute on function cbs_email_by_apelido(text) to anon, authenticated;

create or replace function cbs_is_authorized()
returns boolean language sql security definer stable as $$
  select exists (select 1 from cbs_usuarios where email = auth.jwt() ->> 'email');
$$;
create or replace function cbs_posicao_atual()
returns text language sql security definer stable as $$
  select posicao from cbs_usuarios where email = auth.jwt() ->> 'email';
$$;
create or replace function cbs_comissionado_atual()
returns bigint language sql security definer stable as $$
  select comissionado_id from cbs_usuarios where email = auth.jwt() ->> 'email';
$$;

alter table cbs_usuarios enable row level security;
drop policy if exists "cbs_usuarios - só autorizados" on cbs_usuarios;
create policy "cbs_usuarios - só autorizados" on cbs_usuarios
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

-- ============================================================
-- 2. REDE COMERCIAL (comissionados)
-- ============================================================
create table if not exists cbs_comissionados (
  id bigserial primary key,
  nome text not null,
  telefone text,
  email text,
  pix text,
  status text not null default 'Ativo' check (status in ('Ativo','Inativo')),
  indicado_por bigint references cbs_comissionados(id) on delete set null,
  socio_vinculado text references cbs_usuarios(email) on delete set null, -- marca que esse cadastro representa a participação de um sócio como comissionado
  contrato_status text not null default 'Pendente' check (contrato_status in ('Pendente','Assinado')),
  contrato_data date,
  contrato_path text, -- arquivo do termo assinado, guardado no bucket privado cbs-contratos
  observacoes text,
  created_at timestamptz default now()
);
alter table cbs_comissionados add column if not exists socio_vinculado text references cbs_usuarios(email) on delete set null;
alter table cbs_comissionados add column if not exists contrato_status text not null default 'Pendente';
do $$ begin
  alter table cbs_comissionados add constraint cbs_comissionados_contrato_status_check check (contrato_status in ('Pendente','Assinado'));
exception when duplicate_object then null; end $$;
alter table cbs_comissionados add column if not exists contrato_data date;
alter table cbs_comissionados add column if not exists contrato_path text;

alter table cbs_comissionados enable row level security;
drop policy if exists "cbs_comissionados - só autorizados" on cbs_comissionados;
-- Sócio/Operacional veem tudo. Comercial só enxerga o próprio cadastro (pra quando o portal existir).
create policy "cbs_comissionados - acesso" on cbs_comissionados
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and id = cbs_comissionado_atual())
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

-- ============================================================
-- 3. NEGÓCIOS (relacionamento com o cliente) + divisão de comissão
-- ============================================================
create table if not exists cbs_negocios (
  id bigserial primary key,
  empresa_cliente text not null,
  cnpj text,
  data_inicio date,
  status text not null default 'Ativo' check (status in ('Ativo','Encerrado','Cancelado')),
  situacao_sicoob text not null default 'Indicado' check (situacao_sicoob in ('Indicado','Documentação enviada','Em análise no banco','Conta aberta','Recusado')),
  aprovado_por text references cbs_usuarios(email) on delete set null, -- NULL = aguardando aprovação de um sócio antes de poder negociar
  aprovado_em timestamptz,
  observacoes text,
  created_at timestamptz default now()
);
alter table cbs_negocios add column if not exists situacao_sicoob text not null default 'Indicado';
do $$ begin
  alter table cbs_negocios add constraint cbs_negocios_situacao_sicoob_check check (situacao_sicoob in ('Indicado','Documentação enviada','Em análise no banco','Conta aberta','Recusado'));
exception when duplicate_object then null; end $$;
alter table cbs_negocios add column if not exists aprovado_por text references cbs_usuarios(email) on delete set null;
alter table cbs_negocios add column if not exists aprovado_em timestamptz;
-- migração ÚNICA: só passa a exigir aprovação pra negócio NOVO — tudo que já existia antes dessa
-- coluna existir fica retroativamente aprovado, pra não travar nada em andamento. Usa uma data FIXA
-- como corte (não "now()") — assim é seguro rodar esse arquivo de novo no futuro sem aprovar sozinho
-- um negócio genuinamente pendente criado depois dessa data.
update cbs_negocios set aprovado_por = 'bruno.rivero@gmail.com', aprovado_em = created_at
  where aprovado_por is null and created_at < '2026-08-20 00:00:00+00';

alter table cbs_negocios enable row level security;
drop policy if exists "cbs_negocios - só autorizados" on cbs_negocios;
-- Comercial só vê negócios em que o próprio comissionado_id participa da divisão.
create policy "cbs_negocios - acesso" on cbs_negocios
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and exists (
      select 1 from cbs_negocio_comissionados nc where nc.negocio_id = cbs_negocios.id and nc.comissionado_id = cbs_comissionado_atual()
    ))
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

create table if not exists cbs_negocio_comissionados (
  id bigserial primary key,
  negocio_id bigint not null references cbs_negocios(id) on delete cascade,
  comissionado_id bigint not null references cbs_comissionados(id) on delete restrict,
  percentual numeric(6,2) not null default 0,
  principal boolean not null default false,
  unique (negocio_id, comissionado_id)
);

alter table cbs_negocio_comissionados enable row level security;
drop policy if exists "cbs_negocio_comissionados - só autorizados" on cbs_negocio_comissionados;
create policy "cbs_negocio_comissionados - acesso" on cbs_negocio_comissionados
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

-- ============================================================
-- 4. RECEBIMENTOS (lançamento do extrato do banco) + splits calculados
-- ============================================================
create table if not exists cbs_recebimentos (
  id bigserial primary key,
  negocio_id bigint not null references cbs_negocios(id) on delete restrict,
  data date not null,
  referencia text,
  valor_recebido numeric(14,2) not null,
  percentual_imposto numeric(6,2) not null default 0,
  valor_imposto numeric(14,2) not null default 0,
  percentual_agente numeric(6,2) not null default 0,
  valor_agente numeric(14,2) not null default 0,
  percentual_corplink numeric(6,2) not null default 0,
  valor_corplink numeric(14,2) not null default 0,
  valor_liquido numeric(14,2) not null default 0, -- Lucro Líquido (já sem Agente Banco e CorpLink)
  observacoes text,
  created_at timestamptz default now()
);
alter table cbs_recebimentos add column if not exists percentual_corplink numeric(6,2) not null default 0;
alter table cbs_recebimentos add column if not exists valor_corplink numeric(14,2) not null default 0;

alter table cbs_recebimentos enable row level security;
drop policy if exists "cbs_recebimentos - só autorizados" on cbs_recebimentos;
create policy "cbs_recebimentos - acesso" on cbs_recebimentos
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and exists (
      select 1 from cbs_recebimento_splits s where s.recebimento_id = cbs_recebimentos.id and s.comissionado_id = cbs_comissionado_atual()
    ))
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

create table if not exists cbs_recebimento_splits (
  id bigserial primary key,
  recebimento_id bigint not null references cbs_recebimentos(id) on delete cascade,
  comissionado_id bigint not null references cbs_comissionados(id) on delete restrict,
  percentual numeric(6,2) not null default 0,
  valor numeric(14,2) not null default 0,
  status_pagamento text not null default 'Pendente' check (status_pagamento in ('Pendente','Pago')),
  data_pagamento date,
  comprovante_path text -- caminho do arquivo no Storage (bucket cbs-comprovantes), preenchido ao marcar como Pago
);
alter table cbs_recebimento_splits add column if not exists comprovante_path text;

alter table cbs_recebimento_splits enable row level security;
drop policy if exists "cbs_recebimento_splits - só autorizados" on cbs_recebimento_splits;
create policy "cbs_recebimento_splits - acesso" on cbs_recebimento_splits
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

-- ============================================================
-- 5. CONFIGURAÇÕES (linha única: % imposto padrão, % Agente Banco padrão)
-- ============================================================
create table if not exists cbs_config (
  id int primary key default 1 check (id = 1),
  imposto_pct numeric(6,2) not null default 0,
  agente_pct numeric(6,2) not null default 50,
  corplink_pct numeric(6,2) not null default 20,
  mes_fechado_ate text -- "AAAA-MM": recebimentos com data <= esse mês ficam travados pra edição/exclusão
);
insert into cbs_config (id) values (1) on conflict (id) do nothing;
alter table cbs_config add column if not exists corplink_pct numeric(6,2) not null default 20;
alter table cbs_config add column if not exists mes_fechado_ate text;

alter table cbs_config enable row level security;
drop policy if exists "cbs_config - só autorizados" on cbs_config;
create policy "cbs_config - acesso" on cbs_config
  for all using (cbs_posicao_atual() in ('Sócio','Operacional')) with check (cbs_posicao_atual() in ('Sócio','Operacional'));

-- ============================================================
-- 6. TRILHA DE AUDITORIA (quem alterou o quê, com valor antigo/novo)
-- ============================================================
create table if not exists cbs_audit_log (
  id bigserial primary key,
  tabela text not null,
  registro_id bigint,
  operacao text not null check (operacao in ('INSERT','UPDATE','DELETE')),
  usuario_email text,
  dados_antigos jsonb,
  dados_novos jsonb,
  created_at timestamptz default now()
);

alter table cbs_audit_log enable row level security;
drop policy if exists "cbs_audit_log - só autorizados leem" on cbs_audit_log;
create policy "cbs_audit_log - só sócio/operacional leem" on cbs_audit_log
  for select using (cbs_posicao_atual() in ('Sócio','Operacional'));

create or replace function cbs_audit_trigger()
returns trigger language plpgsql security definer as $$
begin
  insert into cbs_audit_log(tabela, registro_id, operacao, usuario_email, dados_antigos, dados_novos)
  values (
    TG_TABLE_NAME, coalesce(new.id, old.id), TG_OP, auth.jwt() ->> 'email',
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

drop trigger if exists cbs_audit_recebimentos on cbs_recebimentos;
create trigger cbs_audit_recebimentos after insert or update or delete on cbs_recebimentos for each row execute function cbs_audit_trigger();
drop trigger if exists cbs_audit_recebimento_splits on cbs_recebimento_splits;
create trigger cbs_audit_recebimento_splits after insert or update or delete on cbs_recebimento_splits for each row execute function cbs_audit_trigger();
drop trigger if exists cbs_audit_negocios on cbs_negocios;
create trigger cbs_audit_negocios after insert or update or delete on cbs_negocios for each row execute function cbs_audit_trigger();
drop trigger if exists cbs_audit_negocio_comissionados on cbs_negocio_comissionados;
create trigger cbs_audit_negocio_comissionados after insert or update or delete on cbs_negocio_comissionados for each row execute function cbs_audit_trigger();

-- ============================================================
-- 7. SÓCIOS AUTORIZADOS
-- ============================================================
insert into cbs_usuarios (email, nome, posicao) values
  ('bruno.rivero@gmail.com', 'Bruno Rivero', 'Sócio'),
  ('vickcampanario@gmail.com', 'Vinicius', 'Sócio')
on conflict (email) do update set nome = excluded.nome, posicao = excluded.posicao;

-- ============================================================
-- 8. STORAGE — bucket privado pra comprovantes de pagamento
-- ============================================================
insert into storage.buckets (id, name, public)
values ('cbs-comprovantes', 'cbs-comprovantes', false)
on conflict (id) do nothing;

drop policy if exists "cbs-comprovantes - acesso" on storage.objects;
create policy "cbs-comprovantes - acesso" on storage.objects
  for all using (bucket_id = 'cbs-comprovantes' and cbs_is_authorized())
  with check (bucket_id = 'cbs-comprovantes' and cbs_is_authorized());

-- ============================================================
-- 9. RETIRADAS / PRÓ-LABORE — registro à parte, não entra em nenhum cálculo
-- ============================================================
create table if not exists cbs_retiradas (
  id bigserial primary key,
  usuario_email text not null references cbs_usuarios(email) on delete cascade,
  tipo text not null default 'Pró-labore' check (tipo in ('Pró-labore','Retirada de lucro','Outro')),
  valor numeric(14,2) not null,
  data date not null,
  observacoes text,
  created_at timestamptz default now()
);

alter table cbs_retiradas enable row level security;
drop policy if exists "cbs_retiradas - acesso" on cbs_retiradas;
create policy "cbs_retiradas - acesso" on cbs_retiradas
  for all using (cbs_posicao_atual() in ('Sócio','Operacional'))
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

drop trigger if exists cbs_audit_retiradas on cbs_retiradas;
create trigger cbs_audit_retiradas after insert or update or delete on cbs_retiradas for each row execute function cbs_audit_trigger();

-- ============================================================
-- 10. AJUSTES — Estorno/Clawback, Adiantamento e Ajuste Manual (mesmo mecanismo)
-- ============================================================
-- Gera uma linha negativa no extrato do comissionado, abatendo do saldo a pagar (não altera nenhum
-- recebimento/split já gravado — é aditivo, então nunca reescreve o passado. Serve também como o
-- "Ajuste Manual no mês atual" pra corrigir um recebimento de mês já fechado, em vez de editar o antigo.
create table if not exists cbs_ajustes (
  id bigserial primary key,
  tipo text not null check (tipo in ('Estorno','Adiantamento','Ajuste Manual')),
  comissionado_id bigint not null references cbs_comissionados(id) on delete cascade,
  negocio_id bigint references cbs_negocios(id) on delete set null,
  valor numeric(14,2) not null check (valor > 0), -- sempre positivo; o "abate" é aplicado no cálculo do extrato/saldo
  data date not null,
  motivo text,
  created_at timestamptz default now()
);

alter table cbs_ajustes enable row level security;
drop policy if exists "cbs_ajustes - acesso" on cbs_ajustes;
create policy "cbs_ajustes - acesso" on cbs_ajustes
  for all using (
    cbs_posicao_atual() in ('Sócio','Operacional')
    or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
  )
  with check (cbs_posicao_atual() in ('Sócio','Operacional'));

drop trigger if exists cbs_audit_ajustes on cbs_ajustes;
create trigger cbs_audit_ajustes after insert or update or delete on cbs_ajustes for each row execute function cbs_audit_trigger();

-- ============================================================
-- 11. STORAGE — bucket privado pro termo de confidencialidade (NDA) assinado
-- ============================================================
insert into storage.buckets (id, name, public)
values ('cbs-contratos', 'cbs-contratos', false)
on conflict (id) do nothing;

drop policy if exists "cbs-contratos - acesso" on storage.objects;
create policy "cbs-contratos - acesso" on storage.objects
  for all using (bucket_id = 'cbs-contratos' and cbs_is_authorized())
  with check (bucket_id = 'cbs-contratos' and cbs_is_authorized());
