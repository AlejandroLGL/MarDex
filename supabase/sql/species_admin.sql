-- ============================================================================
-- MarDex — Catálogo de especies editable desde el panel de admin
-- Ejecutar en Supabase Studio → SQL Editor (Dashboard del proyecto).
-- Idempotente: se puede volver a pegar y ejecutar sin peligro.
--
-- Después de ejecutar este archivo, ejecuta species_seed.sql UNA VEZ para
-- volcar en la tabla el catálogo de 182 especies que hoy vive en species.json.
-- ============================================================================

create table if not exists public.species (
  id text primary key,
  cat text not null,
  "order" text not null,
  name text not null,
  sci text not null,
  region text,
  zones text[] not null default '{}',
  code text,
  size text,
  habitat text,
  depth text,
  speed text,
  diet text,
  rarity integer,
  blurb text,
  photo_url text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.species enable row level security;

-- Lectura pública: el catálogo lo ve cualquiera, con sesión o sin ella.
drop policy if exists "species_select_all" on public.species;
create policy "species_select_all" on public.species
  for select using (true);

-- Escritura solo para admins (insertar, editar, borrar).
drop policy if exists "species_write_admin" on public.species;
create policy "species_write_admin" on public.species
  for all
  using (exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin))
  with check (exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin));

create or replace function public.species_touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists species_touch_updated_at on public.species;
create trigger species_touch_updated_at
  before update on public.species
  for each row execute function public.species_touch_updated_at();

-- Elimina una especie SOLO si ningún usuario la ha avistado todavía. Usa
-- SECURITY DEFINER porque hay que comprobar avistamientos de todos los
-- usuarios, no solo los del admin que llama (la RLS de `sightings` limita
-- a cada uno a ver solo los suyos). Así se evita borrar por error el
-- catálogo bajo avistamientos y logros que la gente ya tiene guardados.
create or replace function public.admin_delete_species(p_species_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_is_admin boolean;
  v_count integer;
begin
  select p.is_admin into v_is_admin from public.profiles p where p.id = auth.uid();
  if not coalesce(v_is_admin, false) then
    raise exception 'No autorizado';
  end if;

  select count(*) into v_count from public.sightings where species_id = p_species_id;
  if v_count > 0 then
    raise exception 'No se puede eliminar: % usuario(s) tienen avistamientos de esta especie', v_count;
  end if;

  delete from public.species where id = p_species_id;
end;
$$;

revoke all on function public.admin_delete_species(text) from public;
revoke all on function public.admin_delete_species(text) from anon;
grant execute on function public.admin_delete_species(text) to authenticated;

-- Bucket de Storage para las fotos que suban los admins desde el panel.
-- Las especies que nadie haya tocado todavía siguen sirviendo su foto desde
-- el repositorio (especies/imagenes/...); en el momento en que un admin sube
-- una foto nueva, `photo_url` pasa a tener prioridad para todo el mundo.
insert into storage.buckets (id, name, public)
values ('species-photos', 'species-photos', true)
on conflict (id) do nothing;

drop policy if exists "species_photos_read" on storage.objects;
create policy "species_photos_read" on storage.objects
  for select using (bucket_id = 'species-photos');

drop policy if exists "species_photos_write_admin" on storage.objects;
create policy "species_photos_write_admin" on storage.objects
  for insert with check (
    bucket_id = 'species-photos'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

drop policy if exists "species_photos_update_admin" on storage.objects;
create policy "species_photos_update_admin" on storage.objects
  for update using (
    bucket_id = 'species-photos'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );

drop policy if exists "species_photos_delete_admin" on storage.objects;
create policy "species_photos_delete_admin" on storage.objects
  for delete using (
    bucket_id = 'species-photos'
    and exists(select 1 from public.profiles p where p.id = auth.uid() and p.is_admin)
  );
