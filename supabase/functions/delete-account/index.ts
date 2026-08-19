// Elimina la cuenta del usuario que llama a la función. Requiere la
// service role key (SUPABASE_SERVICE_ROLE_KEY, inyectada automáticamente
// por Supabase en toda Edge Function — no hay que configurar ningún
// secreto nuevo) porque borrar un usuario de auth.users solo se puede
// hacer con la API de administración, nunca con la anon/authenticated key
// del cliente.
//
// Body: ninguno. La identidad de quien llama sale del JWT de la cabecera
// Authorization (verify_jwt = true en config.toml ya obliga a que sea
// válido antes de que este código se ejecute).
// Respuesta (JSON): { ok: true } o { error: string }

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const authHeader = req.headers.get("Authorization") ?? "";
  const jwt = authHeader.replace(/^Bearer\s+/i, "");
  if (!jwt) return json({ error: "Falta el token de autenticación" }, 401);

  // Averigua quién llama a partir de su propio JWT (con la anon key,
  // solo para validar/leer el usuario — nunca para el borrado en sí).
  const userRes = await fetch(`${SUPABASE_URL}/auth/v1/user`, {
    headers: {
      Authorization: `Bearer ${jwt}`,
      apikey: Deno.env.get("SUPABASE_ANON_KEY") ?? "",
    },
  });
  if (!userRes.ok) return json({ error: "Token inválido o caducado" }, 401);
  const user = await userRes.json();
  if (!user?.id) return json({ error: "No se pudo identificar al usuario" }, 401);

  // Borrado real con la service role key. Se asume que las tablas
  // dependientes (profiles, sightings, favorites...) tienen sus claves
  // foráneas a auth.users(id)/profiles(id) con ON DELETE CASCADE; si no
  // fuera así, quedarían filas huérfanas que habría que limpiar aparte.
  const delRes = await fetch(`${SUPABASE_URL}/auth/v1/admin/users/${user.id}`, {
    method: "DELETE",
    headers: {
      Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
      apikey: SERVICE_ROLE_KEY,
    },
  });
  if (!delRes.ok) {
    const detail = await delRes.text();
    return json({ error: "No se pudo eliminar la cuenta", detail }, 502);
  }

  return json({ ok: true });
});
