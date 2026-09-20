-- ============================================================================
-- MarDex — Añade "Pulpo común" (Octopus vulgaris) al catálogo
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente (upsert por id).
--
-- La foto NO se sube desde aquí (Claude no tiene acceso al Storage del
-- proyecto): tras ejecutar este SQL, entra en Perfil → Admin → Especies →
-- "Pulpo común" → Cambiar foto, y sube la imagen del pulpo entre la
-- posidonia. Se queda guardada en el bucket species-photos con la ruta
-- pulpocomun.jpg automáticamente.
-- ============================================================================

insert into public.species (
  id, cat, "order", name, sci, region, zones, code,
  size, habitat, depth, speed, diet, rarity, blurb, tags
) values (
  'pulpocomun', 'molusco', 'Octopoda', 'Pulpo común', 'Octopus vulgaris',
  'Global', array['mediterraneo','cantabrico','canarias'], 'MOL-22',
  'Hasta 1 m (brazos incluidos)',
  'Fondos de arena, roca y praderas marinas',
  '0–100 m', 'Moderada', 'Crustáceos, moluscos y peces pequeños', 1,
  'Maestro del camuflaje: cambia de color y textura de piel en fracciones de segundo para mimetizarse con el fondo. De hábitos solitarios y nocturnos, se refugia en grietas y madrigueras excavadas en arena o entre rocas, rodeadas a veces de conchas y restos de presas.',
  array[]::text[]
)
on conflict (id) do update set
  cat = excluded.cat,
  "order" = excluded."order",
  name = excluded.name,
  sci = excluded.sci,
  region = excluded.region,
  zones = excluded.zones,
  code = excluded.code,
  size = excluded.size,
  habitat = excluded.habitat,
  depth = excluded.depth,
  speed = excluded.speed,
  diet = excluded.diet,
  rarity = excluded.rarity,
  blurb = excluded.blurb,
  tags = excluded.tags;
