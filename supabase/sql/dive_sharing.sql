-- ============================================================================
-- MarDex — Etiquetar compañeros y compartir inmersiones del logbook
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente (CREATE TABLE IF NOT
-- EXISTS / CREATE OR REPLACE / políticas con DROP previo).
--
-- Tres tablas nuevas:
--   - dive_tags: etiqueta a otro usuario de MarDex en una inmersión, con un
--     rol (compañero/instructor/divemaster/otro). Desde que se añadió
--     dive_tags.status (más abajo), etiquetar ya NO da acceso de lectura
--     inmediato: la persona etiquetada tiene que aceptar la etiqueta
--     primero (accept_dive_tag/decline_dive_tag), igual que una invitación.
--   - dive_collaborators: representa el modo "compartir tal cual" (edición
--     compartida). Se rellena desde accept_dive_invite(), nunca a mano desde
--     el cliente, por eso no tiene políticas de insert/update/delete para
--     `authenticated` — solo la función (SECURITY DEFINER) puede escribir.
--   - dive_invites: la invitación en sí (pendiente/aceptada/rechazada). El
--     snapshot `dive_summary` (nombre, fecha, lugar...) se guarda en el
--     momento de compartir para poder mostrar una vista previa en la
--     pantalla de invitación SIN necesitar que quien la recibe pueda leer ya
--     la fila de `dives` (que, hasta aceptar, no le pertenece ni está
--     etiquetado ni es colaborador).
--
-- Guardamos también en `dive_tags` el nombre/username/avatar del usuario
-- etiquetado tal cual los devolvió search_users() en el momento de etiquetar
-- (tagged_name/tagged_username/tagged_avatar_url), en vez de hacer un JOIN
-- contra `profiles` al leer: `profiles` de otras personas no es legible por
-- select directo en este proyecto (search_users/get_friend_data/
-- get_banner_urls son RPC aparte para eso), así que un JOIN fallaría o
-- devolvería null bajo RLS. Es una foto fija: si esa persona cambia de
-- nombre después, el tag no se actualiza solo, pero evita tener que crear
-- una RPC nueva solo para esto.
--
-- Las políticas nuevas en `dives` (select/update) se SUMAN a las 4 ya
-- existentes en logbook.sql (dives_select_own, dives_insert_own,
-- dives_update_own, dives_delete_own): Postgres combina con OR varias
-- políticas PERMISSIVE del mismo comando, así que esto amplía el acceso sin
-- debilitar el de los propietarios.
-- ============================================================================

create table if not exists public.dive_tags (
  id uuid primary key default gen_random_uuid(),
  dive_id uuid not null references public.dives(id) on delete cascade,
  tagged_user_id uuid not null references public.profiles(id) on delete cascade,
  role text not null default 'companero' check (role in ('companero','instructor','divemaster','otro')),
  tagged_name text not null,
  tagged_username text,
  tagged_avatar_url text,
  created_by uuid not null default auth.uid(),
  created_at timestamptz not null default now(),
  unique(dive_id, tagged_user_id)
);
create index if not exists dive_tags_dive_id_idx on public.dive_tags(dive_id);
create index if not exists dive_tags_tagged_user_id_idx on public.dive_tags(tagged_user_id);

-- Mismo motivo que dive_collaborators.dive_number más abajo: a quien solo
-- está ETIQUETADO (sin ser colaborador — no tiene por qué haber aceptado
-- compartir la edición) tampoco tiene por qué coincidirle el Nº de
-- inmersión con el de quien le etiquetó. Nunca se sugiere un valor aquí
-- (a diferencia de dive_collaborators, no hay un "aceptar" al que
-- enganchar la sugerencia): lo pone la propia persona a mano la primera
-- vez que quiere verlo en su numeración, vía set_my_tag_dive_number.
alter table public.dive_tags add column if not exists dive_number integer;

-- Ciclo de vida de una etiqueta — igual que dive_invites, pero sin tabla
-- aparte: etiquetar a alguien ya no le da acceso de lectura inmediato
-- (ver dives_select_tagged_or_collab más abajo, que ahora exige
-- status='accepted'); la persona etiquetada tiene que aceptar antes de que
-- la inmersión le aparezca en el logbook. 'forked': la persona etiquetada
-- editó algo que no era su propio Nº y se le creó una copia independiente
-- (ver fork_tagged_dive) — deja de tener sentido seguir dándole acceso a
-- la fila original por esta vía, pero se conserva la fila (no se borra)
-- para que el propietario siga viendo el historial de quién estuvo
-- etiquetado en sus chips de compañeros.
--
-- Backfill explícito: las etiquetas creadas ANTES de esta columna ya daban
-- acceso inmediato (ese era el comportamiento de antes) — se marcan como
-- 'accepted' antes de imponer el default 'pending', para no hacer
-- desaparecer de ningún logbook una inmersión que ya se veía.
alter table public.dive_tags add column if not exists status text;
update public.dive_tags set status = 'accepted' where status is null;
alter table public.dive_tags alter column status set default 'pending';
alter table public.dive_tags alter column status set not null;
alter table public.dive_tags drop constraint if exists dive_tags_status_check;
alter table public.dive_tags add constraint dive_tags_status_check
  check (status in ('pending','accepted','declined','forked'));

create table if not exists public.dive_collaborators (
  id uuid primary key default gen_random_uuid(),
  dive_id uuid not null references public.dives(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  unique(dive_id, user_id)
);
create index if not exists dive_collaborators_dive_id_idx on public.dive_collaborators(dive_id);

-- El Nº de inmersión es una cuenta corrida PERSONAL de cada buceador — en
-- una inmersión compartida "tal cual" (mismo registro, una sola fila en
-- `dives`), la numeración de cada colaborador normalmente no coincide con
-- la del propietario (uno puede ir por la 30, otro por la 180). dives.
-- dive_number sigue siendo el número del propietario; este campo guarda el
-- número de CADA colaborador para esa misma inmersión, sugerido al
-- aceptar (ver accept_dive_invite) y editable después (ver
-- set_my_collab_dive_number más abajo).
alter table public.dive_collaborators add column if not exists dive_number integer;

create table if not exists public.dive_invites (
  id uuid primary key default gen_random_uuid(),
  dive_id uuid not null references public.dives(id) on delete cascade,
  from_user_id uuid not null default auth.uid() references public.profiles(id) on delete cascade,
  to_user_id uuid references public.profiles(id) on delete cascade,
  mode text not null check (mode in ('live','copy')),
  status text not null default 'pending' check (status in ('pending','accepted','declined')),
  dive_summary jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index if not exists dive_invites_to_user_id_idx on public.dive_invites(to_user_id);
create index if not exists dive_invites_from_user_id_idx on public.dive_invites(from_user_id);

-- Marca si quien recibe la invitación ya la ha visto en la campana de
-- notificaciones — independiente de `status`: una invitación puede llevar
-- días "vista" y seguir "pending" hasta que se acepte o rechace.
alter table public.dive_invites add column if not exists seen_at timestamptz;

alter table public.dive_tags enable row level security;
alter table public.dive_collaborators enable row level security;
alter table public.dive_invites enable row level security;

-- Dos funciones SECURITY DEFINER para comprobar propiedad/colaboración de
-- una inmersión SIN pasar por las políticas RLS de `dives`/`dive_
-- collaborators` al hacerlo.
--
-- Son imprescindibles: las políticas de más abajo en `dives` consultan
-- dive_tags/dive_collaborators, y las de dive_tags/dive_collaborators
-- consultaban antes `dives` directamente — eso es una referencia circular
-- entre las políticas de dos tablas (dives → dive_tags → dives → ...) que
-- Postgres corta con el error "infinite recursion detected in policy for
-- relation dives", y que PostgREST/supabase-js reportan como un error de
-- red normal y corriente en vez de explicarlo. Como loadDives() en el
-- frontend trata cualquier error como "no hay inmersiones" (dives = []),
-- el síntoma visible era que el logbook se veía vacío, como si se hubieran
-- borrado — no se borró nada, solo se volvió ilegible por este bucle.
--
-- Al pasar por una función SECURITY DEFINER, cuyo propietario (el rol que
-- la crea desde el SQL Editor) es también el propietario de las tablas,
-- Postgres la exime de RLS automáticamente (así es como admin_delete_
-- species(), en species_admin.sql, ya puede contar avistamientos de todos
-- los usuarios aunque la RLS de `sightings` los limite a los propios). Eso
-- corta el ciclo: dive_tags/dive_collaborators ya no vuelven a disparar la
-- RLS de `dives` al consultarla.
create or replace function public.is_dive_owner(p_dive_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.dives d where d.id = p_dive_id and d.user_id = auth.uid());
$$;
revoke all on function public.is_dive_owner(uuid) from public;
revoke all on function public.is_dive_owner(uuid) from anon;
grant execute on function public.is_dive_owner(uuid) to authenticated;

create or replace function public.is_dive_collaborator(p_dive_id uuid)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists(select 1 from public.dive_collaborators c where c.dive_id = p_dive_id and c.user_id = auth.uid());
$$;
revoke all on function public.is_dive_collaborator(uuid) from public;
revoke all on function public.is_dive_collaborator(uuid) from anon;
grant execute on function public.is_dive_collaborator(uuid) to authenticated;

-- ── dive_tags ────────────────────────────────────────────────────────────
drop policy if exists "dive_tags_select" on public.dive_tags;
create policy "dive_tags_select" on public.dive_tags
  for select using (
    tagged_user_id = auth.uid()
    or public.is_dive_owner(dive_id)
    or public.is_dive_collaborator(dive_id)
  );

drop policy if exists "dive_tags_insert" on public.dive_tags;
create policy "dive_tags_insert" on public.dive_tags
  for insert with check (
    created_by = auth.uid()
    and public.is_dive_owner(dive_id)
  );

drop policy if exists "dive_tags_update" on public.dive_tags;
create policy "dive_tags_update" on public.dive_tags
  for update using (
    public.is_dive_owner(dive_id)
  ) with check (
    public.is_dive_owner(dive_id)
  );

-- Borrar un tag lo puede hacer el propietario de la inmersión, o la propia
-- persona etiquetada (para "desetiquetarse" si no quiere figurar).
drop policy if exists "dive_tags_delete" on public.dive_tags;
create policy "dive_tags_delete" on public.dive_tags
  for delete using (
    tagged_user_id = auth.uid()
    or public.is_dive_owner(dive_id)
  );

-- ── dive_collaborators ──────────────────────────────────────────────────
-- Solo lectura por RLS: la fila la crea accept_dive_invite() (SECURITY
-- DEFINER), nunca el cliente directamente.
drop policy if exists "dive_collaborators_select" on public.dive_collaborators;
create policy "dive_collaborators_select" on public.dive_collaborators
  for select using (
    user_id = auth.uid()
    or public.is_dive_owner(dive_id)
  );

-- Un colaborador puede dejar de serlo (quitar la inmersión compartida de su
-- propio logbook) sin tocar la fila de `dives`, que sigue siendo del
-- propietario — igual que dive_tags_delete deja "desetiquetarse" a quien
-- está etiquetado. El propietario no necesita una política aparte para
-- esto: ya puede borrar la fila de `dives` entera si quiere (dives_delete_own
-- en logbook.sql), lo que arrastra sus dive_collaborators por el ON DELETE
-- CASCADE de más arriba.
drop policy if exists "dive_collaborators_delete" on public.dive_collaborators;
create policy "dive_collaborators_delete" on public.dive_collaborators
  for delete using (
    user_id = auth.uid()
  );

-- ── dive_invites ────────────────────────────────────────────────────────
-- Un enlace de invitación "abierto" (to_user_id null) NO es legible por
-- select directo aquí a propósito: si lo fuera, cualquier usuario podría
-- listar TODAS las invitaciones abiertas de todo el mundo con un simple
-- `select * from dive_invites`, no solo la suya. Para esas, el cliente usa
-- get_dive_invite(uuid) más abajo, que solo devuelve la fila pedida por id
-- (igual que un enlace "cualquiera con el enlace" normal: hace falta
-- conocer el id, no se puede enumerar).
drop policy if exists "dive_invites_select" on public.dive_invites;
create policy "dive_invites_select" on public.dive_invites
  for select using (from_user_id = auth.uid() or to_user_id = auth.uid());

drop policy if exists "dive_invites_insert" on public.dive_invites;
create policy "dive_invites_insert" on public.dive_invites
  for insert with check (
    from_user_id = auth.uid()
    and public.is_dive_owner(dive_id)
  );

-- El estado (aceptada/rechazada) solo lo cambia accept_dive_invite(); lo
-- único que el cliente puede hacer directamente es retirar una invitación
-- que él mismo envió y sigue pendiente.
drop policy if exists "dive_invites_delete" on public.dive_invites;
create policy "dive_invites_delete" on public.dive_invites
  for delete using (from_user_id = auth.uid());

-- ── dives: acceso ampliado a etiquetados/colaboradores ─────────────────
-- `and t.status = 'accepted'`: una etiqueta pendiente/rechazada/con fork ya
-- hecho no da acceso de lectura — solo una aceptada (ver el ciclo de vida
-- en el comentario de dive_tags.status más arriba).
drop policy if exists "dives_select_tagged_or_collab" on public.dives;
create policy "dives_select_tagged_or_collab" on public.dives
  for select using (
    exists(select 1 from public.dive_tags t where t.dive_id = dives.id and t.tagged_user_id = auth.uid() and t.status = 'accepted')
    or exists(select 1 from public.dive_collaborators c where c.dive_id = dives.id and c.user_id = auth.uid())
  );

-- Edición compartida real: solo en modo "live" (dive_collaborators), nunca
-- solo por estar etiquetado.
drop policy if exists "dives_update_collab" on public.dives;
create policy "dives_update_collab" on public.dives
  for update using (
    exists(select 1 from public.dive_collaborators c where c.dive_id = dives.id and c.user_id = auth.uid())
  ) with check (
    exists(select 1 from public.dive_collaborators c where c.dive_id = dives.id and c.user_id = auth.uid())
  );

-- Pestaña "Amigos" del logbook: un amigo ve el detalle COMPLETO de tus
-- inmersiones aunque no esté etiquetado ni sea colaborador (decisión
-- confirmada con el usuario — no es un resumen). "Amigo" = fila aceptada
-- en friend_requests en cualquiera de los dos sentidos (sender/receiver),
-- mismo criterio que ya usa el frontend para "Mis amigos". Solo SELECT:
-- un amigo nunca puede editar ni borrar tu inmersión por esta vía — para
-- eso sigue haciendo falta etiqueta+aceptar o "Compartir inmersión".
drop policy if exists "dives_select_friends" on public.dives;
create policy "dives_select_friends" on public.dives
  for select using (
    exists(
      select 1 from public.friend_requests fr
      where fr.status = 'accepted'
        and ((fr.sender_id = auth.uid() and fr.receiver_id = dives.user_id)
          or (fr.receiver_id = auth.uid() and fr.sender_id = dives.user_id))
    )
  );

-- ── RPCs ────────────────────────────────────────────────────────────────

-- Lee una invitación por id sin permitir enumerarlas todas (ver comentario
-- de dive_invites_select más arriba). Usada por la pantalla que se abre al
-- tocar un enlace de invitación (?diveInvite=<id>), incluidas las abiertas
-- (to_user_id null), antes de que quien la recibe tenga ningún otro acceso
-- a esa inmersión.
create or replace function public.get_dive_invite(p_invite_id uuid)
returns public.dive_invites
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_invite public.dive_invites;
begin
  select * into v_invite from public.dive_invites where id = p_invite_id;
  if v_invite.id is null then
    raise exception 'Invitación no encontrada';
  end if;
  if v_invite.to_user_id is not null
     and v_invite.to_user_id <> auth.uid()
     and v_invite.from_user_id <> auth.uid() then
    raise exception 'No autorizado';
  end if;
  return v_invite;
end;
$$;

revoke all on function public.get_dive_invite(uuid) from public;
revoke all on function public.get_dive_invite(uuid) from anon;
grant execute on function public.get_dive_invite(uuid) to authenticated;

-- Acepta o rechaza una invitación. SECURITY DEFINER + `for update` sobre la
-- fila para que, en un enlace abierto, dos personas no puedan "ganar" la
-- misma invitación a la vez (la segunda en llegar encuentra status ya
-- distinto de 'pending' y falla con una excepción clara).
--
-- Modo 'live': añade a quien acepta como colaborador (dive_collaborators) —
-- la inmersión sigue siendo la misma fila, ahora editable por ambos.
-- Modo 'copy': clona la fila de `dives` (nueva, propiedad de quien acepta)
-- y también sus `sightings` vía dive_id, para que queden dos registros
-- totalmente independientes.
--
-- Devuelve el id de la inmersión resultante (la original en modo 'live', la
-- copia nueva en modo 'copy'), o null si se rechaza.
--
-- El Nº de inmersión del propietario NUNCA se copia a quien acepta (ver el
-- comentario de dive_collaborators.dive_number más arriba): se le sugiere
-- en su lugar el siguiente de SU PROPIA numeración — el mayor dive_number
-- entre sus propias inmersiones y sus colaboraciones en otras, +1 — tanto
-- en modo 'live' (se guarda en dive_collaborators.dive_number) como en
-- 'copy' (se guarda directamente como dive_number de la copia, un campo
-- más de su propia fila, editable después como cualquier otro).
create or replace function public.accept_dive_invite(p_invite_id uuid, p_action text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_invite public.dive_invites;
  v_acceptor_id uuid := auth.uid();
  v_new_dive_id uuid;
  v_next_number integer;
begin
  if p_action not in ('accept','decline') then
    raise exception 'Acción no válida: %', p_action;
  end if;

  select * into v_invite from public.dive_invites where id = p_invite_id for update;
  if v_invite.id is null then
    raise exception 'Invitación no encontrada';
  end if;
  if v_invite.status <> 'pending' then
    raise exception 'Esta invitación ya se resolvió';
  end if;
  if v_invite.to_user_id is not null and v_invite.to_user_id <> v_acceptor_id then
    raise exception 'Esta invitación no es para ti';
  end if;
  if v_invite.from_user_id = v_acceptor_id then
    raise exception 'No puedes aceptar tu propia invitación';
  end if;

  if p_action = 'decline' then
    update public.dive_invites
      set status = 'declined', to_user_id = coalesce(to_user_id, v_acceptor_id)
      where id = p_invite_id;
    return null;
  end if;

  select coalesce(max(n), 0) + 1 into v_next_number
  from (
    select dive_number as n from public.dives where user_id = v_acceptor_id and dive_number is not null
    union all
    select dive_number as n from public.dive_collaborators where user_id = v_acceptor_id and dive_number is not null
    union all
    select dive_number as n from public.dive_tags where tagged_user_id = v_acceptor_id and dive_number is not null
  ) nums;

  if v_invite.mode = 'live' then
    insert into public.dive_collaborators (dive_id, user_id, dive_number)
    values (v_invite.dive_id, v_acceptor_id, v_next_number)
    on conflict (dive_id, user_id) do nothing;
    v_new_dive_id := v_invite.dive_id;
  else
    insert into public.dives (
      user_id, dive_number, date, entry_time, exit_time, duration_min,
      site_name, dive_name, location_text, lat, lng,
      approach_type, dive_club, dive_center, seabed_type,
      water_temp, air_temp, entry_pressure, exit_pressure,
      buddy, notes, suit_type, air_type, current, visibility_m,
      max_depth_m, safety_stop_m, deco_stop_m, weight_kg, tank_liters, tank_material,
      main_photo, notes_photos
    )
    select
      v_acceptor_id, v_next_number, date, entry_time, exit_time, duration_min,
      site_name, dive_name, location_text, lat, lng,
      approach_type, dive_club, dive_center, seabed_type,
      water_temp, air_temp, entry_pressure, exit_pressure,
      buddy, notes, suit_type, air_type, current, visibility_m,
      max_depth_m, safety_stop_m, deco_stop_m, weight_kg, tank_liters, tank_material,
      main_photo, notes_photos
    from public.dives where id = v_invite.dive_id
    returning id into v_new_dive_id;

    insert into public.sightings (
      species_id, title, location_text, comment, lat, lng, date, environment,
      photo, size_observed, depth_observed, dive_id, user_id
    )
    select
      species_id, title, location_text, comment, lat, lng, date, environment,
      photo, size_observed, depth_observed, v_new_dive_id, v_acceptor_id
    from public.sightings where dive_id = v_invite.dive_id;
  end if;

  update public.dive_invites
    set status = 'accepted', to_user_id = coalesce(to_user_id, v_acceptor_id)
    where id = p_invite_id;

  return v_new_dive_id;
end;
$$;

revoke all on function public.accept_dive_invite(uuid, text) from public;
revoke all on function public.accept_dive_invite(uuid, text) from anon;
grant execute on function public.accept_dive_invite(uuid, text) to authenticated;

-- Marca como vistas todas las invitaciones pendientes dirigidas a quien
-- llama. Se usa SECURITY DEFINER para no tener que añadir una política de
-- UPDATE a dive_invites solo para esto — así `status`/`mode`/etc. siguen
-- sin poder tocarse desde el cliente más que a través de
-- accept_dive_invite(), y esta función solo puede cambiar seen_at.
create or replace function public.mark_dive_invites_seen()
returns void
language sql
security definer
set search_path = public
as $$
  update public.dive_invites set seen_at = now()
  where to_user_id = auth.uid() and status = 'pending' and seen_at is null;
$$;

revoke all on function public.mark_dive_invites_seen() from public;
revoke all on function public.mark_dive_invites_seen() from anon;
grant execute on function public.mark_dive_invites_seen() to authenticated;

-- Deja a un colaborador cambiar SU PROPIO número de inmersión en una
-- inmersión compartida "tal cual" (ver dive_collaborators.dive_number más
-- arriba) — SECURITY DEFINER para no tener que abrir una política de
-- UPDATE completa sobre dive_collaborators solo para este único campo.
create or replace function public.set_my_collab_dive_number(p_dive_id uuid, p_number integer)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dive_collaborators
  set dive_number = p_number
  where dive_id = p_dive_id and user_id = auth.uid();
$$;

revoke all on function public.set_my_collab_dive_number(uuid, integer) from public;
revoke all on function public.set_my_collab_dive_number(uuid, integer) from anon;
grant execute on function public.set_my_collab_dive_number(uuid, integer) to authenticated;

-- Mismo mecanismo que set_my_collab_dive_number, pero para quien solo está
-- ETIQUETADO en la inmersión (sin ser colaborador): su Nº tampoco tiene por
-- qué coincidir con el de quien le etiquetó, y dive_tags_update (más
-- arriba) solo lo puede tocar el propietario — por eso hace falta esta
-- función aparte en vez de dejarle hacer un update normal.
create or replace function public.set_my_tag_dive_number(p_dive_id uuid, p_number integer)
returns void
language sql
security definer
set search_path = public
as $$
  update public.dive_tags
  set dive_number = p_number
  where dive_id = p_dive_id and tagged_user_id = auth.uid();
$$;

revoke all on function public.set_my_tag_dive_number(uuid, integer) from public;
revoke all on function public.set_my_tag_dive_number(uuid, integer) from anon;
grant execute on function public.set_my_tag_dive_number(uuid, integer) to authenticated;

-- Vista previa de mis etiquetas pendientes (para la tarjeta de "X te ha
-- etiquetado..." antes de aceptar). A diferencia de dive_invites, dive_tags
-- no guarda un snapshot propio (dive_summary) con el nombre de quien
-- etiqueta y datos de la inmersión — y ahora que una etiqueta pendiente ya
-- NO da acceso de lectura a `dives` (ver dives_select_tagged_or_collab),
-- el cliente no podría leer esos datos por su cuenta. SECURITY DEFINER para
-- leer `dives`/`profiles` de quien etiquetó sin pasar por su RLS, limitado
-- a lo justo para la tarjeta (nunca toda la fila de `dives`).
create or replace function public.get_pending_dive_tags()
returns table(
  id uuid, dive_id uuid, role text, created_at timestamptz,
  owner_name text, owner_username text,
  dive_date date, dive_site_name text, dive_dive_name text
)
language sql
stable
security definer
set search_path = public
as $$
  select
    t.id, t.dive_id, t.role, t.created_at,
    p.name as owner_name, p.username as owner_username,
    d.date as dive_date, d.site_name as dive_site_name, d.dive_name as dive_dive_name
  from public.dive_tags t
  join public.dives d on d.id = t.dive_id
  join public.profiles p on p.id = d.user_id
  where t.tagged_user_id = auth.uid() and t.status = 'pending'
  order by t.created_at desc;
$$;

revoke all on function public.get_pending_dive_tags() from public;
revoke all on function public.get_pending_dive_tags() from anon;
grant execute on function public.get_pending_dive_tags() to authenticated;

-- Acepta/rechaza una etiqueta — mismo papel que accept_dive_invite pero
-- para dive_tags. SECURITY DEFINER porque dive_tags_update (más arriba)
-- solo lo puede tocar el propietario de la inmersión, no quien está
-- etiquetado. Solo puede resolver una etiqueta 'pending' — ya aceptada,
-- rechazada o con fork hecho no se puede volver a tocar por aquí.
create or replace function public.accept_dive_tag(p_tag_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.dive_tags
  set status = 'accepted'
  where id = p_tag_id and tagged_user_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'Etiqueta no encontrada o ya resuelta';
  end if;
end;
$$;

revoke all on function public.accept_dive_tag(uuid) from public;
revoke all on function public.accept_dive_tag(uuid) from anon;
grant execute on function public.accept_dive_tag(uuid) to authenticated;

create or replace function public.decline_dive_tag(p_tag_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.dive_tags
  set status = 'declined'
  where id = p_tag_id and tagged_user_id = auth.uid() and status = 'pending';
  if not found then
    raise exception 'Etiqueta no encontrada o ya resuelta';
  end if;
end;
$$;

revoke all on function public.decline_dive_tag(uuid) from public;
revoke all on function public.decline_dive_tag(uuid) from anon;
grant execute on function public.decline_dive_tag(uuid) to authenticated;

-- Si alguien solo etiquetado (no colaborador real) edita cualquier campo
-- que no sea su propio Nº, la inmersión deja de ser "compartida" para él y
-- pasa a ser una copia independiente — nunca se toca la fila original del
-- propietario. p_payload trae el mismo shape que ya construye
-- readDiveForm() en el cliente (incluye dive_number, pero se ignora: el Nº
-- de la copia es el que la persona ya tenía puesto en su propia etiqueta,
-- vía set_my_tag_dive_number — no el del formulario). Mismo patrón de clonado
-- de sightings que el modo 'copy' de accept_dive_invite.
create or replace function public.fork_tagged_dive(p_dive_id uuid, p_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_tag public.dive_tags;
  v_new_dive_id uuid;
begin
  select * into v_tag from public.dive_tags
  where dive_id = p_dive_id and tagged_user_id = auth.uid() and status = 'accepted';
  if v_tag.id is null then
    raise exception 'No tienes una etiqueta aceptada en esta inmersión';
  end if;

  insert into public.dives (
    user_id, dive_number, date, entry_time, exit_time, duration_min,
    site_name, dive_name, location_text, lat, lng,
    approach_type, dive_club, dive_center, seabed_type,
    water_temp, air_temp, entry_pressure, exit_pressure,
    buddy, notes, suit_type, air_type, current, visibility_m,
    max_depth_m, safety_stop_m, deco_stop_m, weight_kg, tank_liters, tank_material,
    main_photo, notes_photos
  )
  values (
    auth.uid(), v_tag.dive_number,
    (p_payload->>'date')::date,
    nullif(p_payload->>'entry_time','')::time,
    nullif(p_payload->>'exit_time','')::time,
    (p_payload->>'duration_min')::numeric,
    p_payload->>'site_name', p_payload->>'dive_name', p_payload->>'location_text',
    (p_payload->>'lat')::double precision, (p_payload->>'lng')::double precision,
    p_payload->>'approach_type', p_payload->>'dive_club', p_payload->>'dive_center', p_payload->>'seabed_type',
    (p_payload->>'water_temp')::numeric, (p_payload->>'air_temp')::numeric,
    (p_payload->>'entry_pressure')::numeric, (p_payload->>'exit_pressure')::numeric,
    p_payload->>'buddy', p_payload->>'notes', p_payload->>'suit_type', p_payload->>'air_type',
    p_payload->>'current', (p_payload->>'visibility_m')::numeric,
    (p_payload->>'max_depth_m')::numeric, (p_payload->>'safety_stop_m')::numeric, (p_payload->>'deco_stop_m')::numeric,
    (p_payload->>'weight_kg')::numeric, (p_payload->>'tank_liters')::numeric, p_payload->>'tank_material',
    p_payload->>'main_photo', coalesce(p_payload->'notes_photos', '[]'::jsonb)
  )
  returning id into v_new_dive_id;

  insert into public.sightings (
    species_id, title, location_text, comment, lat, lng, date, environment,
    photo, size_observed, depth_observed, dive_id, user_id
  )
  select
    species_id, title, location_text, comment, lat, lng, date, environment,
    photo, size_observed, depth_observed, v_new_dive_id, auth.uid()
  from public.sightings where dive_id = p_dive_id;

  update public.dive_tags set status = 'forked' where id = v_tag.id;

  return v_new_dive_id;
end;
$$;

revoke all on function public.fork_tagged_dive(uuid, jsonb) from public;
revoke all on function public.fork_tagged_dive(uuid, jsonb) from anon;
grant execute on function public.fork_tagged_dive(uuid, jsonb) to authenticated;
