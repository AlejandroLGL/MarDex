-- ============================================================================
-- MarDex — Licencia/nivel de buceo e inmersiones totales en la tarjeta de
-- cada persona (perfil propio, tarjetas de amigos, perfil de amigo).
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente.
--
-- "Inmersiones totales" NO es un recuento de filas en `dives` (eso ya se
-- usa para el ranking en ranking_global.sql, con otro propósito): aquí se
-- pide expresamente el número (`dive_number`) de la ÚLTIMA inmersión
-- registrada por fecha, porque ese número lo lleva cada buceador como
-- cuenta corrida propia desde antes de usar MarDex si hace falta (p. ej.
-- si ya llevaba 150 inmersiones al apuntarse, sigue numerando desde 151 en
-- vez de reiniciar en 1). Si hay empate de fecha, se desempata por
-- created_at desc (la introducida más recientemente en MarDex).
-- ============================================================================

alter table public.profiles add column if not exists cert_level text;

-- get_friends/search_users/get_pending_requests/get_friend_data no exponen
-- cert_level ni esto (igual que pasaba con banner_url en friends_banner.sql):
-- no están versionadas en el repo, así que en vez de tocarlas se añade esta
-- función aparte y el frontend combina los datos.
--
-- La última inmersión de alguien no tiene por qué ser una propia: puede ser
-- una compartida "tal cual" en la que colabora (ver dive_sharing.sql,
-- dive_collaborators.dive_number — ahí el Nº es el suyo propio, no el del
-- propietario de la fila). Por eso se mira lo más reciente por fecha entre
-- sus propias inmersiones Y sus colaboraciones, no solo `dives`.
--
-- `where n is not null` (añadido tras un caso real): una colaboración
-- compartida puede tener fecha más reciente que cualquier inmersión propia
-- pero sin que el colaborador haya puesto aún su propio número (campo "tu
-- propio número" al editar una inmersión compartida) — si esa fila sin
-- número "ganara" por ser la más reciente, total_dives saldría NULL aunque
-- la persona sí tenga inmersiones numeradas. Se ignoran las filas sin
-- número y se cae a la más reciente que sí lo tenga.
create or replace function public.get_profile_dive_stats(user_ids uuid[])
returns table(id uuid, cert_level text, total_dives integer)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.cert_level,
    (
      select n from (
        select d.dive_number as n, d.date as dt, d.created_at as ca
        from public.dives d where d.user_id = p.id
        union all
        select dc.dive_number as n, d2.date as dt, d2.created_at as ca
        from public.dive_collaborators dc
        join public.dives d2 on d2.id = dc.dive_id
        where dc.user_id = p.id
      ) all_dives
      where n is not null
      order by dt desc, ca desc
      limit 1
    ) as total_dives
  from public.profiles p
  where p.id = any(user_ids);
$$;

revoke all on function public.get_profile_dive_stats(uuid[]) from public;
revoke all on function public.get_profile_dive_stats(uuid[]) from anon;
grant execute on function public.get_profile_dive_stats(uuid[]) to authenticated;
