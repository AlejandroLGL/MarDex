-- ============================================================================
-- MarDex — Pantalla de inicio (banner de perfil + layout de widgets)
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente.
--
-- No hace falta un bucket de Storage nuevo para el banner: reutiliza el
-- bucket "avatars" que ya existe, con la foto guardada en
-- `${user_id}/banner.jpg` junto a `${user_id}/avatar.jpg`. Si la política
-- de ese bucket ya está acotada al prefijo `${user_id}/` (lo habitual),
-- no hace falta tocar nada más ahí.
-- ============================================================================

alter table public.profiles add column if not exists banner_url text;
alter table public.profiles add column if not exists home_layout jsonb not null default '[]'::jsonb;
