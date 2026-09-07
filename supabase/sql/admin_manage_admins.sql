-- ============================================================================
-- MarDex — Gestión de administradores desde el panel de admin
-- Ejecutar en Supabase Studio → SQL Editor (Dashboard del proyecto).
-- Idempotente: se puede volver a pegar y ejecutar sin peligro.
--
-- Añade un "propietario" permanente (tu cuenta): nadie, ni tú mismo desde el
-- panel, puede quitarle el admin. El resto de admins se pueden añadir o
-- quitar libremente desde la nueva pestaña "Administradores".
-- ============================================================================

alter table public.profiles add column if not exists is_owner boolean not null default false;

-- Marca tu cuenta (alexandrolealganado@gmail.com) como propietaria y admin.
-- Si alguna vez cambias de correo, vuelve a ejecutar esta parte con el
-- correo nuevo (no hace nada si ya no encuentra ninguna fila).
update public.profiles
set is_owner = true, is_admin = true
where id = (select id from auth.users where email = 'alexandrolealganado@gmail.com');

-- Lista de usuarios para la pestaña "Administradores": nombre, correo y rol.
-- No sustituye a get_admin_users() (la tabla de estadísticas), que sigue
-- igual; esta es una consulta aparte, más pequeña, solo para decidir a
-- quién promover o degradar.
create or replace function public.admin_list_users_for_roles()
returns table (
  id uuid,
  name text,
  username text,
  email text,
  is_admin boolean,
  is_owner boolean,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_is_admin boolean;
begin
  select p.is_admin into v_caller_is_admin from public.profiles p where p.id = auth.uid();
  if not coalesce(v_caller_is_admin, false) then
    raise exception 'No autorizado';
  end if;

  -- Cast explícito de cada columna: sin esto, si alguna columna real (p.ej.
  -- `name`/`username` como varchar en vez de text) no coincide byte a byte
  -- con el tipo declarado arriba, Postgres da "structure of query does not
  -- match function result type" aunque el tipo sea compatible.
  return query
    select
      p.id::uuid,
      p.name::text,
      p.username::text,
      au.email::text,
      p.is_admin::boolean,
      p.is_owner::boolean,
      au.created_at::timestamptz
    from public.profiles p
    join auth.users au on au.id = p.id
    order by p.is_owner desc, p.is_admin desc, au.created_at asc;
end;
$$;

revoke all on function public.admin_list_users_for_roles() from public;
revoke all on function public.admin_list_users_for_roles() from anon;
grant execute on function public.admin_list_users_for_roles() to authenticated;

-- Cambia el estado de admin de otro usuario. Bloqueado en dos casos:
-- el objetivo es el propietario (nunca se le puede quitar el admin), o el
-- que llama intenta cambiarse a sí mismo (evita quedarse fuera del panel
-- por accidente; para dejar de ser admin que lo haga otro admin).
create or replace function public.admin_set_is_admin(p_user_id uuid, p_is_admin boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_caller_is_admin boolean;
  v_target_is_owner boolean;
begin
  select is_admin into v_caller_is_admin from public.profiles where id = auth.uid();
  if not coalesce(v_caller_is_admin, false) then
    raise exception 'No autorizado';
  end if;

  if p_user_id = auth.uid() then
    raise exception 'No puedes cambiar tu propio estado de administrador';
  end if;

  select is_owner into v_target_is_owner from public.profiles where id = p_user_id;
  if coalesce(v_target_is_owner, false) then
    raise exception 'Este usuario es el propietario permanente: no se le puede quitar el admin';
  end if;

  update public.profiles set is_admin = p_is_admin where id = p_user_id;
end;
$$;

revoke all on function public.admin_set_is_admin(uuid, boolean) from public;
revoke all on function public.admin_set_is_admin(uuid, boolean) from anon;
grant execute on function public.admin_set_is_admin(uuid, boolean) to authenticated;
