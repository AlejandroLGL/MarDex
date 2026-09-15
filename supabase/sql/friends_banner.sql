-- ============================================================================
-- MarDex — Banner de otros usuarios en el menú de Amigos
-- Ejecutar en Supabase Studio → SQL Editor. Idempotente.
--
-- get_friends / search_users / get_pending_requests / get_friend_data ya
-- devuelven avatar_url para cualquier usuario (no solo el propio) a través
-- de funciones existentes que no están versionadas en este repo, así que no
-- se tocan aquí para no arriesgar su definición exacta. En su lugar, esta
-- función nueva expone banner_url (un campo igual de público que avatar_url)
-- para una lista de IDs, y el frontend la combina con esos datos.
-- ============================================================================

create or replace function public.get_banner_urls(user_ids uuid[])
returns table(id uuid, banner_url text)
language sql
security definer
set search_path = public
as $$
  select p.id, p.banner_url from public.profiles p where p.id = any(user_ids);
$$;

grant execute on function public.get_banner_urls(uuid[]) to authenticated;
