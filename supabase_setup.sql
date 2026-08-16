-- CBS — setup Supabase
-- Rodar no SQL Editor do projeto pxcqyzbgfbwwkazmonzx (mesmo projeto do BIG GTD / Finanças Casa / Agenda Renata)
-- Todas as tabelas prefixadas "cbs_" pra ficar isolado dos outros apps no mesmo projeto.

-- ============================================================
-- 1. USUÁRIOS AUTORIZADOS (allowlist + perfil de cada um)
-- ============================================================
-- Só quem estiver aqui (por e-mail) consegue ler/gravar qualquer tabela do CBS.
-- Cadastre aqui o e-mail exato usado no Supabase Auth de cada sócio/operacional.
create table if not exists cbs_usuarios (
  email text primary key,
  nome text not null,
  posicao text not null check (posicao in ('Sócio','Comercial','Operacional')),
  created_at timestamptz default now()
);

-- Função que checa se quem está logado (pelo e-mail do token) está na allowlist.
-- security definer = ignora RLS da própria cbs_usuarios ao checar (senão vira referência circular).
create or replace function cbs_is_authorized()
returns boolean
language sql
security definer
stable
as $$
  select exists (
    select 1 from cbs_usuarios where email = auth.jwt() ->> 'email'
  );
$$;

alter table cbs_usuarios enable row level security;
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
  observacoes text,
  created_at timestamptz default now()
);

alter table cbs_comissionados enable row level security;
create policy "cbs_comissionados - só autorizados" on cbs_comissionados
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

-- ============================================================
-- 3. NEGÓCIOS (relacionamento com o cliente) + divisão de comissão
-- ============================================================
create table if not exists cbs_negocios (
  id bigserial primary key,
  empresa_cliente text not null,
  cnpj text,
  data_inicio date,
  status text not null default 'Ativo' check (status in ('Ativo','Encerrado','Cancelado')),
  observacoes text,
  created_at timestamptz default now()
);

alter table cbs_negocios enable row level security;
create policy "cbs_negocios - só autorizados" on cbs_negocios
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

-- fonte única do % de cada comissionado no negócio (Recebimento só lê daqui)
create table if not exists cbs_negocio_comissionados (
  id bigserial primary key,
  negocio_id bigint not null references cbs_negocios(id) on delete cascade,
  comissionado_id bigint not null references cbs_comissionados(id) on delete restrict,
  percentual numeric(6,2) not null default 0,
  principal boolean not null default false,
  unique (negocio_id, comissionado_id)
);

alter table cbs_negocio_comissionados enable row level security;
create policy "cbs_negocio_comissionados - só autorizados" on cbs_negocio_comissionados
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

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
  valor_liquido numeric(14,2) not null default 0, -- Lucro Líquido CBS
  observacoes text,
  created_at timestamptz default now()
);

alter table cbs_recebimentos enable row level security;
create policy "cbs_recebimentos - só autorizados" on cbs_recebimentos
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

create table if not exists cbs_recebimento_splits (
  id bigserial primary key,
  recebimento_id bigint not null references cbs_recebimentos(id) on delete cascade,
  comissionado_id bigint not null references cbs_comissionados(id) on delete restrict,
  percentual numeric(6,2) not null default 0,
  valor numeric(14,2) not null default 0,
  status_pagamento text not null default 'Pendente' check (status_pagamento in ('Pendente','Pago')),
  data_pagamento date
);

alter table cbs_recebimento_splits enable row level security;
create policy "cbs_recebimento_splits - só autorizados" on cbs_recebimento_splits
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

-- ============================================================
-- 5. CONFIGURAÇÕES (linha única: % imposto padrão, % Agente Banco padrão)
-- ============================================================
create table if not exists cbs_config (
  id int primary key default 1 check (id = 1), -- garante uma única linha
  imposto_pct numeric(6,2) not null default 0,
  agente_pct numeric(6,2) not null default 50
);
insert into cbs_config (id) values (1) on conflict (id) do nothing;

alter table cbs_config enable row level security;
create policy "cbs_config - só autorizados" on cbs_config
  for all using (cbs_is_authorized()) with check (cbs_is_authorized());

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
create policy "cbs_audit_log - só autorizados leem" on cbs_audit_log
  for select using (cbs_is_authorized());
-- ninguém edita/apaga log manualmente — só o trigger (security definer) grava.

create or replace function cbs_audit_trigger()
returns trigger
language plpgsql
security definer
as $$
begin
  insert into cbs_audit_log(tabela, registro_id, operacao, usuario_email, dados_antigos, dados_novos)
  values (
    TG_TABLE_NAME,
    coalesce(new.id, old.id),
    TG_OP,
    auth.jwt() ->> 'email',
    case when TG_OP in ('UPDATE','DELETE') then to_jsonb(old) else null end,
    case when TG_OP in ('UPDATE','INSERT') then to_jsonb(new) else null end
  );
  return coalesce(new, old);
end;
$$;

create trigger cbs_audit_recebimentos
  after insert or update or delete on cbs_recebimentos
  for each row execute function cbs_audit_trigger();

create trigger cbs_audit_recebimento_splits
  after insert or update or delete on cbs_recebimento_splits
  for each row execute function cbs_audit_trigger();

create trigger cbs_audit_negocios
  after insert or update or delete on cbs_negocios
  for each row execute function cbs_audit_trigger();

create trigger cbs_audit_negocio_comissionados
  after insert or update or delete on cbs_negocio_comissionados
  for each row execute function cbs_audit_trigger();

-- ============================================================
-- 7. SÓCIOS AUTORIZADOS
-- ============================================================
-- Esses e-mails são exatamente os das contas já criadas no Supabase Auth
-- (bruno.rivero@gmail.com já existia; vickcampanario@gmail.com foi criada agora).
insert into cbs_usuarios (email, nome, posicao) values
  ('bruno.rivero@gmail.com', 'Bruno Rivero', 'Sócio'),
  ('vickcampanario@gmail.com', 'Vinicius', 'Sócio')
on conflict (email) do update set nome = excluded.nome, posicao = excluded.posicao;
