-- ============================================================================
-- MarDex — Foto destacada del perfil (tarjeta "Fotos destacadas" del
-- carrusel de inicio). Ejecutar en Supabase Studio → SQL Editor.
-- Idempotente.
--
-- Mismo bucket de Storage que avatar/banner (ver home_screen.sql): no hace
-- falta un bucket nuevo. La foto se guarda en `${user_id}/featured.jpg`,
-- junto a `${user_id}/avatar.jpg` y `${user_id}/banner.jpg`.
-- ============================================================================

alter table public.profiles add column if not exists featured_photo_url text;
