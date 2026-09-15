-- ============================================================================
-- MarDex — Nombres locales (tags) + alta de "Lecha" en la tabla `species`
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente.
--
-- Contexto: una PR ajena a esta sesión (feat/species-local-tags) añadió el
-- campo `tags` (nombres locales, mostrados como etiquetas en la ficha de
-- cada especie) y una especie nueva ("Lecha") directamente en el array
-- embebido de index.html, sin pasar por el editor de especies del panel de
-- admin. Como la app ahora lee el catálogo de esta tabla en tiempo de
-- ejecución (ver species_admin.sql), ese cambio nunca llegó a producción:
-- la tabla no tenía columna `tags`, y "Lecha" no existía como fila.
-- ============================================================================

alter table public.species add column if not exists tags text[] not null default '{}';

-- Alta de Lecha (Lichia amia) — no existía en la tabla.
insert into public.species (id, cat, "order", name, sci, region, zones, code, size, habitat, depth, speed, diet, rarity, blurb, tags)
values (
  'lecha', 'pez', 'Carangiformes', 'Lecha', 'Lichia amia', 'Mediterráneo',
  ARRAY['mediterraneo','cantabrico','canarias'], 'PEZ-80', '2 m',
  'Aguas costeras y pelágicas', '0–200 m', 'Muy rápida',
  'Peces, calamares y crustáceos', 3,
  'Depredador plateado y estilizado con la mandíbula inferior prominente y la cola en media luna. Caza en solitario o en grupos reducidos en aguas abiertas y costeras del Atlántico oriental y el Mediterráneo; muy apreciado en pesca deportiva por su fuerza y resistencia.',
  ARRAY['leerfish','garrick','licha']
)
on conflict (id) do update set tags = excluded.tags;

-- Nombres locales de las otras 12 especies que la misma PR había tageado
-- (estas sí existían ya en la tabla, solo les faltaba `tags`).
update public.species set tags = ARRAY['pastinaca','chucho','raya aguijón'] where id = 'latigo';
update public.species set tags = ARRAY['loro','pez loro','cotorra'] where id = 'vieja';
update public.species set tags = ARRAY['morena oscura'] where id = 'morenanegra';
update public.species set tags = ARRAY['lampuga','mahi-mahi','pez delfín'] where id = 'dorado';
update public.species set tags = ARRAY['róbalo','branzino'] where id = 'lubina';
update public.species set tags = ARRAY['serraneta'] where id = 'baila';
update public.species set tags = ARRAY['palometa'] where id = 'chopa';
update public.species set tags = ARRAY['araña de mar','cangrejo araña'] where id = 'centollo';
update public.species set tags = ARRAY['araña canaria','flecha de mar'] where id = 'cangrejoaranacanarias';
update public.species set tags = ARRAY['cangrejo araña','cangrejo pinto'] where id = 'maranuela';
update public.species set tags = ARRAY['langosta canaria','cigarra'] where id = 'cigarramar';
update public.species set tags = ARRAY['ronco'] where id = 'roncador';
