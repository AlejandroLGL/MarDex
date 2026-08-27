-- ============================================================================
-- MarDex — Ranking global de usuarios
-- Ejecutar en Supabase Studio → SQL Editor (Dashboard del proyecto).
-- Idempotente: se puede volver a pegar y ejecutar sin peligro (CREATE OR REPLACE).
--
-- ANTES DE EJECUTAR: esta función asume que la tabla `sightings` tiene una
-- columna `user_id` que identifica al dueño de cada avistamiento. Si en tu
-- proyecto se llama distinto (p.ej. `owner_id`), sustitúyelo en la definición
-- de abajo antes de ejecutar. Puedes comprobar el nombre real con:
--
--   select column_name, data_type from information_schema.columns
--   where table_schema = 'public' and table_name = 'sightings';
-- ============================================================================

create or replace function public.get_leaderboard()
returns table (
  id uuid,
  name text,
  username text,
  avatar_url text,
  species_count bigint,
  species_count_libre bigint,
  species_count_acuario bigint,
  sightings_count bigint,
  sightings_count_libre bigint,
  sightings_count_acuario bigint,
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
    coalesce(agg.species_count, 0)           as species_count,
    coalesce(agg.species_count_libre, 0)     as species_count_libre,
    coalesce(agg.species_count_acuario, 0)   as species_count_acuario,
    coalesce(agg.sightings_count, 0)         as sightings_count,
    coalesce(agg.sightings_count_libre, 0)   as sightings_count_libre,
    coalesce(agg.sightings_count_acuario, 0) as sightings_count_acuario,
    agg.max_depth_m,
    (p.id = auth.uid())                      as is_me
  from public.profiles p
  left join (
    select
      s.user_id,
      count(distinct s.species_id)                                          as species_count,
      count(distinct s.species_id) filter (where s.environment = 'libre')   as species_count_libre,
      count(distinct s.species_id) filter (where s.environment = 'acuario') as species_count_acuario,
      count(*)                                                              as sightings_count,
      count(*) filter (where s.environment = 'libre')                       as sightings_count_libre,
      count(*) filter (where s.environment = 'acuario')                     as sightings_count_acuario,
      max(s.depth_observed)                                                 as max_depth_m
    from public.sightings s
    group by s.user_id
  ) agg on agg.user_id = p.id
  -- Solo se listan usuarios con privacidad "pública", más siempre tu propia
  -- fila (para que puedas ver dónde quedarías si activaras la visibilidad
  -- pública). Si prefieres que "amigos" también cuente como visible en el
  -- ranking global, cambia la condición por: p.privacy in ('publico','amigos')
  where p.privacy = 'publico' or p.id = auth.uid()
  order by species_count desc, sightings_count desc;
$$;

revoke all on function public.get_leaderboard() from public;
revoke all on function public.get_leaderboard() from anon;
grant execute on function public.get_leaderboard() to authenticated;
