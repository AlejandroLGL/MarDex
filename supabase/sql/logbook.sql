-- ============================================================================
-- MarDex — Logbook de inmersiones
-- Ejecutar en Supabase Studio → SQL Editor (Dashboard del proyecto).
-- Idempotente: se puede volver a pegar y ejecutar sin peligro
-- (CREATE TABLE IF NOT EXISTS / ADD COLUMN IF NOT EXISTS / políticas con DROP
-- previo).
-- ============================================================================

create table if not exists public.dives (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null default auth.uid() references auth.users(id) on delete cascade,
  created_at timestamptz not null default now(),

  dive_number integer,
  date date not null,
  entry_time time,
  exit_time time,
  duration_min numeric,

  site_name text,
  dive_name text,
  location_text text,
  lat double precision,
  lng double precision,

  approach_type text,
  dive_club text,
  dive_center text,
  seabed_type text,

  water_temp numeric,
  air_temp numeric,
  entry_pressure numeric,
  exit_pressure numeric,

  buddy text,
  notes text,

  suit_type text,
  air_type text,
  current text,
  visibility_m numeric,
  max_depth_m numeric,
  safety_stop_m numeric,
  deco_stop_m numeric,
  weight_kg numeric,
  tank_liters numeric,
  tank_material text
);

alter table public.dives enable row level security;

drop policy if exists "dives_select_own" on public.dives;
create policy "dives_select_own" on public.dives
  for select using (user_id = auth.uid());

drop policy if exists "dives_insert_own" on public.dives;
create policy "dives_insert_own" on public.dives
  for insert with check (user_id = auth.uid());

drop policy if exists "dives_update_own" on public.dives;
create policy "dives_update_own" on public.dives
  for update using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists "dives_delete_own" on public.dives;
create policy "dives_delete_own" on public.dives
  for delete using (user_id = auth.uid());

-- Vincula avistamientos a la inmersión durante la que se registraron (opcional,
-- por eso es nullable: los avistamientos creados desde "Explorar" sin pasar
-- por el logbook siguen funcionando igual que hasta ahora).
alter table public.sightings add column if not exists dive_id uuid references public.dives(id) on delete set null;
