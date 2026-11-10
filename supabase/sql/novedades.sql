-- ============================================================================
-- MarDex — Novedades de la app (tarjeta del carrusel de inicio + pestaña en
-- la campana de notificaciones). Ejecutar en Supabase Studio → SQL Editor.
-- Idempotente.
--
-- Las novedades en sí NO viven en la base de datos: son un array
-- hardcodeado en el frontend (NOVEDADES, en index.html), igual que
-- ZONES/SPECIES — publicar una nueva es un PR/deploy, a propósito (así se
-- controla exactamente qué se publica y cuándo). Lo único que necesita
-- persistir en servidor es qué fue lo último que cada usuario ya vio, para
-- poder mostrar el aviso de "hay algo nuevo" en cualquier dispositivo.
-- ============================================================================

alter table public.profiles add column if not exists last_seen_novedad_id text;
