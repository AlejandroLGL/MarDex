-- ============================================================================
-- MarDex — Ranking global (widget "Ranking" de Inicio)
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente (CREATE OR REPLACE).
--
-- Devuelve UNA fila por usuario con todas las métricas ya agregadas; el
-- frontend ordena por la que el usuario elija (avistamientos, especies,
-- avistamientos por rareza, inmersiones, profundidad máxima) y calcula el
-- puesto. No se limita a N filas porque hace falta la lista entera para
-- saber en qué puesto exacto está uno.
--
-- Igual que get_leaderboard(), asume que `sightings` y `dives` tienen una
-- columna `user_id` con el dueño de cada fila. La rareza sale de la tabla
-- `species` (columna `rarity`, 1–5) uniendo por `species_id`.
-- ============================================================================

create or replace function public.get_global_ranking()
returns table (
  id uuid,
  name text,
  username text,
  avatar_url text,
  sightings_count bigint,
  species_count bigint,
  rarity1_count bigint,
  rarity2_count bigint,
  rarity3_count bigint,
  rarity4_count bigint,
  rarity5_count bigint,
  dives_count bigint,
  max_depth_m numeric,
  is_me boolean
)
language sql
stable
security definer
set search_path = public
as $$
  select
    p.id,
    p.name,
    p.username,
    p.avatar_url,
    coalesce(sg.sightings_count, 0)::bigint          as sightings_count,
    coalesce(sg.species_count, 0)::bigint            as species_count,
    coalesce(sg.rarity1_count, 0)::bigint            as rarity1_count,
    coalesce(sg.rarity2_count, 0)::bigint            as rarity2_count,
    coalesce(sg.rarity3_count, 0)::bigint            as rarity3_count,
    coalesce(sg.rarity4_count, 0)::bigint            as rarity4_count,
    coalesce(sg.rarity5_count, 0)::bigint            as rarity5_count,
    coalesce(dv.dives_count, 0)::bigint              as dives_count,
    -- greatest() ignora los NULL: si solo hay profundidad en un sitio, vale esa.
    greatest(sg.max_depth_m::numeric, dv.max_depth_m::numeric) as max_depth_m,
    (p.id = auth.uid())                              as is_me
  from public.profiles p
  left join (
    select
      s.user_id,
      count(*)                                        as sightings_count,
      count(distinct s.species_id)                    as species_count,
      count(*) filter (where sp.rarity = 1)           as rarity1_count,
      count(*) filter (where sp.rarity = 2)           as rarity2_count,
      count(*) filter (where sp.rarity = 3)           as rarity3_count,
      count(*) filter (where sp.rarity = 4)           as rarity4_count,
      count(*) filter (where sp.rarity = 5)           as rarity5_count,
      max(s.depth_observed)                           as max_depth_m
    from public.sightings s
    left join public.species sp on sp.id = s.species_id
    group by s.user_id
  ) sg on sg.user_id = p.id
  left join (
    select d.user_id, count(*) as dives_count, max(d.max_depth_m) as max_depth_m
    from public.dives d
    group by d.user_id
  ) dv on dv.user_id = p.id
  -- Mismo criterio de privacidad que get_leaderboard(): fuera quien esté en
  -- "privado", salvo uno mismo (para ver siempre el propio puesto).
  where coalesce(p.privacy, 'amigos') != 'privado' or p.id = auth.uid();
$$;

revoke all on function public.get_global_ranking() from public;
revoke all on function public.get_global_ranking() from anon;
grant execute on function public.get_global_ranking() to authenticated;
