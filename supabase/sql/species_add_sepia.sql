-- ============================================================================
-- MarDex — Añade "Sepia común" (Sepia officinalis) al catálogo
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente (upsert por id).
--
-- Sin foto: no se ha adjuntado ninguna esta vez. Tras ejecutar este SQL,
-- puedes subirla desde Perfil → Admin → Especies → "Sepia común" → Cambiar
-- foto (se guarda sola en el bucket species-photos).
-- ============================================================================

insert into public.species (
  id, cat, "order", name, sci, region, zones, code,
  size, habitat, depth, speed, diet, rarity, blurb, tags
) values (
  'sepiacomun', 'molusco', 'Sepiida', 'Sepia común', 'Sepia officinalis',
  'Mediterráneo', array['mediterraneo','cantabrico'], 'MOL-23',
  'Hasta 45 cm de manto',
  'Fondos de arena y fango, y praderas marinas',
  '0–200 m', 'Moderada', 'Crustáceos, peces pequeños y otros moluscos', 2,
  'Como el pulpo, cambia de color y textura de piel para camuflarse o comunicarse, con vistosas oleadas de color durante el cortejo. A diferencia de él conserva una concha interna calcificada, la jibia, que le da flotabilidad y que suele aparecer varada en las playas tras su muerte. Caza al acecho, inmóvil, hasta lanzar dos tentáculos retráctiles para atrapar a su presa.',
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
