-- CBS — Correção de segurança RLS (2026-08-26)
-- "for all using(X) with check(Y)" no Postgres NÃO aplica with check a DELETE,
-- e em cbs_usuarios o with check era largo demais. Corrigido abaixo.
-- Idempotente: pode rodar de novo sem problema.

-- 1. cbs_usuarios
drop policy if exists "cbs_usuarios - só autorizados" on cbs_usuarios;
drop policy if exists "cbs_usuarios - select" on cbs_usuarios;
create policy "cbs_usuarios - select" on cbs_usuarios for select using (cbs_is_authorized());
drop policy if exists "cbs_usuarios - insert" on cbs_usuarios;
create policy "cbs_usuarios - insert" on cbs_usuarios for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_usuarios - update" on cbs_usuarios;
create policy "cbs_usuarios - update" on cbs_usuarios for update using (cbs_is_authorized()) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_usuarios - delete" on cbs_usuarios;
create policy "cbs_usuarios - delete" on cbs_usuarios for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 2. cbs_comissionados
drop policy if exists "cbs_comissionados - só autorizados" on cbs_comissionados;
drop policy if exists "cbs_comissionados - acesso" on cbs_comissionados;
drop policy if exists "cbs_comissionados - select" on cbs_comissionados;
create policy "cbs_comissionados - select" on cbs_comissionados for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and id = cbs_comissionado_atual())
);
drop policy if exists "cbs_comissionados - insert" on cbs_comissionados;
create policy "cbs_comissionados - insert" on cbs_comissionados for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_comissionados - update" on cbs_comissionados;
create policy "cbs_comissionados - update" on cbs_comissionados for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and id = cbs_comissionado_atual())
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_comissionados - delete" on cbs_comissionados;
create policy "cbs_comissionados - delete" on cbs_comissionados for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 3. cbs_negocios
drop policy if exists "cbs_negocios - só autorizados" on cbs_negocios;
drop policy if exists "cbs_negocios - acesso" on cbs_negocios;
drop policy if exists "cbs_negocios - select" on cbs_negocios;
create policy "cbs_negocios - select" on cbs_negocios for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and exists (
    select 1 from cbs_negocio_comissionados nc where nc.negocio_id = cbs_negocios.id and nc.comissionado_id = cbs_comissionado_atual()
  ))
);
drop policy if exists "cbs_negocios - insert" on cbs_negocios;
create policy "cbs_negocios - insert" on cbs_negocios for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_negocios - update" on cbs_negocios;
create policy "cbs_negocios - update" on cbs_negocios for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and exists (
    select 1 from cbs_negocio_comissionados nc where nc.negocio_id = cbs_negocios.id and nc.comissionado_id = cbs_comissionado_atual()
  ))
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_negocios - delete" on cbs_negocios;
create policy "cbs_negocios - delete" on cbs_negocios for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 4. cbs_negocio_comissionados
drop policy if exists "cbs_negocio_comissionados - só autorizados" on cbs_negocio_comissionados;
drop policy if exists "cbs_negocio_comissionados - acesso" on cbs_negocio_comissionados;
drop policy if exists "cbs_negocio_comissionados - select" on cbs_negocio_comissionados;
create policy "cbs_negocio_comissionados - select" on cbs_negocio_comissionados for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
);
drop policy if exists "cbs_negocio_comissionados - insert" on cbs_negocio_comissionados;
create policy "cbs_negocio_comissionados - insert" on cbs_negocio_comissionados for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_negocio_comissionados - update" on cbs_negocio_comissionados;
create policy "cbs_negocio_comissionados - update" on cbs_negocio_comissionados for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_negocio_comissionados - delete" on cbs_negocio_comissionados;
create policy "cbs_negocio_comissionados - delete" on cbs_negocio_comissionados for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 5. cbs_recebimentos
drop policy if exists "cbs_recebimentos - só autorizados" on cbs_recebimentos;
drop policy if exists "cbs_recebimentos - acesso" on cbs_recebimentos;
drop policy if exists "cbs_recebimentos - select" on cbs_recebimentos;
create policy "cbs_recebimentos - select" on cbs_recebimentos for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and exists (
    select 1 from cbs_recebimento_splits s where s.recebimento_id = cbs_recebimentos.id and s.comissionado_id = cbs_comissionado_atual()
  ))
);
drop policy if exists "cbs_recebimentos - insert" on cbs_recebimentos;
create policy "cbs_recebimentos - insert" on cbs_recebimentos for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_recebimentos - update" on cbs_recebimentos;
create policy "cbs_recebimentos - update" on cbs_recebimentos for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and exists (
    select 1 from cbs_recebimento_splits s where s.recebimento_id = cbs_recebimentos.id and s.comissionado_id = cbs_comissionado_atual()
  ))
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_recebimentos - delete" on cbs_recebimentos;
create policy "cbs_recebimentos - delete" on cbs_recebimentos for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 6. cbs_recebimento_splits
drop policy if exists "cbs_recebimento_splits - só autorizados" on cbs_recebimento_splits;
drop policy if exists "cbs_recebimento_splits - acesso" on cbs_recebimento_splits;
drop policy if exists "cbs_recebimento_splits - select" on cbs_recebimento_splits;
create policy "cbs_recebimento_splits - select" on cbs_recebimento_splits for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
);
drop policy if exists "cbs_recebimento_splits - insert" on cbs_recebimento_splits;
create policy "cbs_recebimento_splits - insert" on cbs_recebimento_splits for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_recebimento_splits - update" on cbs_recebimento_splits;
create policy "cbs_recebimento_splits - update" on cbs_recebimento_splits for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_recebimento_splits - delete" on cbs_recebimento_splits;
create policy "cbs_recebimento_splits - delete" on cbs_recebimento_splits for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 7. cbs_ajustes
drop policy if exists "cbs_ajustes - acesso" on cbs_ajustes;
drop policy if exists "cbs_ajustes - select" on cbs_ajustes;
create policy "cbs_ajustes - select" on cbs_ajustes for select using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
);
drop policy if exists "cbs_ajustes - insert" on cbs_ajustes;
create policy "cbs_ajustes - insert" on cbs_ajustes for insert with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_ajustes - update" on cbs_ajustes;
create policy "cbs_ajustes - update" on cbs_ajustes for update using (
  cbs_posicao_atual() in ('Sócio','Operacional')
  or (cbs_posicao_atual()='Comercial' and comissionado_id = cbs_comissionado_atual())
) with check (cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs_ajustes - delete" on cbs_ajustes;
create policy "cbs_ajustes - delete" on cbs_ajustes for delete using (cbs_posicao_atual() in ('Sócio','Operacional'));

-- 8. bucket cbs-comprovantes
drop policy if exists "cbs-comprovantes - acesso" on storage.objects;
drop policy if exists "cbs-comprovantes - select" on storage.objects;
create policy "cbs-comprovantes - select" on storage.objects for select using (bucket_id = 'cbs-comprovantes' and cbs_is_authorized());
drop policy if exists "cbs-comprovantes - insert" on storage.objects;
create policy "cbs-comprovantes - insert" on storage.objects for insert with check (bucket_id = 'cbs-comprovantes' and cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs-comprovantes - update" on storage.objects;
create policy "cbs-comprovantes - update" on storage.objects for update using (bucket_id = 'cbs-comprovantes' and cbs_is_authorized()) with check (bucket_id = 'cbs-comprovantes' and cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs-comprovantes - delete" on storage.objects;
create policy "cbs-comprovantes - delete" on storage.objects for delete using (bucket_id = 'cbs-comprovantes' and cbs_posicao_atual() in ('Sócio','Operacional'));

-- 9. bucket cbs-contratos
drop policy if exists "cbs-contratos - acesso" on storage.objects;
drop policy if exists "cbs-contratos - select" on storage.objects;
create policy "cbs-contratos - select" on storage.objects for select using (bucket_id = 'cbs-contratos' and cbs_is_authorized());
drop policy if exists "cbs-contratos - insert" on storage.objects;
create policy "cbs-contratos - insert" on storage.objects for insert with check (bucket_id = 'cbs-contratos' and cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs-contratos - update" on storage.objects;
create policy "cbs-contratos - update" on storage.objects for update using (bucket_id = 'cbs-contratos' and cbs_is_authorized()) with check (bucket_id = 'cbs-contratos' and cbs_posicao_atual() in ('Sócio','Operacional'));
drop policy if exists "cbs-contratos - delete" on storage.objects;
create policy "cbs-contratos - delete" on storage.objects for delete using (bucket_id = 'cbs-contratos' and cbs_posicao_atual() in ('Sócio','Operacional'));
