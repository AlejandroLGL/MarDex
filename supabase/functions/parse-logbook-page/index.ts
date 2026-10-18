// Lee una foto de una página de logbook de buceo (en papel, de otra app,
// de un ordenador de buceo...) y devuelve los campos de una inmersión que
// se puedan sacar de ahí, usando Gemini (Google AI Studio) — mismo patrón
// que identify-species: la API key vive solo aquí, como secreto de
// Supabase, nunca se expone al cliente.
//
// Body esperado (JSON):
//   { imageBase64: string, mimeType?: string }
// Respuesta (JSON): un objeto con los mismos campos que una fila de
// `dives` que tenga sentido leer de una página de logbook (sin id/
// user_id/created_at/fotos/compañeros — eso no se intenta sacar de la
// foto). Cualquier campo no legible o ausente va como null.

const GEMINI_API_KEY = Deno.env.get("GEMINI_API_KEY");
const GEMINI_MODEL = "gemini-2.5-flash";
const GEMINI_URL = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent`;

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

// El <input type="time"> del formulario solo acepta "HH:MM" con el cero
// delante (p.ej. "09:30", no "9:30") — si se le asigna algo que no
// cumple ese formato exacto, el navegador lo descarta en silencio.
function padTime(v: unknown): string | null {
  if (typeof v !== "string") return null;
  const m = /^(\d{1,2}):(\d{2})$/.exec(v.trim());
  if (!m) return null;
  const h = Number(m[1]), mi = Number(m[2]);
  if (h > 23 || mi > 59) return null;
  return `${String(h).padStart(2, "0")}:${m[2]}`;
}

// Mismas listas de opciones que dvSelect() usa en el formulario de
// inmersión (index.html) — si Gemini no responde con una de estas, se
// descarta ese campo en vez de guardar un valor que el <select> no podría
// representar.
const APPROACH_OPTIONS = ["Costa", "Barco"];
const SEABED_OPTIONS = ["Arena", "Roca", "Posidonia", "Grava", "Fango", "Mixto"];
const AIR_TYPE_OPTIONS = ["Aire", "Nitrox", "Trimix"];
const SUIT_OPTIONS = ["Húmedo", "Semiseco", "Seco"];
const TANK_MATERIAL_OPTIONS = ["Acero", "Aluminio"];
const CURRENT_OPTIONS = ["Nula", "Suave", "Moderada", "Fuerte"];

const NUMBER_FIELDS = [
  "dive_number", "duration_min", "water_temp", "air_temp",
  "entry_pressure", "exit_pressure", "tank_liters", "weight_kg",
  "visibility_m", "max_depth_m", "safety_stop_m", "deco_stop_m",
] as const;
const TEXT_FIELDS = [
  "site_name", "dive_name", "location_text", "dive_center", "dive_club", "notes",
] as const;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!GEMINI_API_KEY) return json({ error: "Falta GEMINI_API_KEY en los secretos de Supabase" }, 500);

  let body: { imageBase64?: string; mimeType?: string };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body no es JSON válido" }, 400);
  }

  const { imageBase64, mimeType } = body;
  if (!imageBase64) return json({ error: "Falta imageBase64" }, 400);

  const prompt = `Eres un ayudante que transcribe hojas de bitácora (logbook) de inmersiones de buceo a datos estructurados, a partir de una foto. La hoja puede estar escrita a mano o impresa, en cualquier idioma, y puede ser de papel o una captura de otra app/ordenador de buceo.

Responde ÚNICAMENTE con un JSON con EXACTAMENTE estas claves (sin texto adicional ni bloques de código). Usa null en cualquier campo que no aparezca en la foto o que no puedas leer con razonable confianza — mejor null que inventar o adivinar un dato:

{
  "dive_number": <entero o null — número de inmersión, cuenta corrida del buceador>,
  "date": "<AAAA-MM-DD o null>",
  "entry_time": "<HH:MM en 24h o null>",
  "exit_time": "<HH:MM en 24h o null>",
  "duration_min": <entero (minutos) o null>,
  "site_name": "<texto o null — lugar/punto de inmersión>",
  "dive_name": "<texto o null — nombre propio de la inmersión, si lo hay>",
  "location_text": "<texto o null — localidad/zona/país>",
  "approach_type": "<una de: ${APPROACH_OPTIONS.join(", ")} — o null>",
  "seabed_type": "<una de: ${SEABED_OPTIONS.join(", ")} — o null>",
  "water_temp": <número (°C) o null>,
  "air_temp": <número (°C) o null>,
  "entry_pressure": <entero (bar, presión de inicio) o null>,
  "exit_pressure": <entero (bar, presión final) o null>,
  "air_type": "<una de: ${AIR_TYPE_OPTIONS.join(", ")} — o null>",
  "tank_liters": <número (litros de la botella) o null>,
  "tank_material": "<una de: ${TANK_MATERIAL_OPTIONS.join(", ")} — o null>",
  "weight_kg": <número (lastre) o null>,
  "suit_type": "<una de: ${SUIT_OPTIONS.join(", ")} — o null>",
  "current": "<una de: ${CURRENT_OPTIONS.join(", ")} — o null>",
  "visibility_m": <número o null>,
  "max_depth_m": <número (profundidad máxima) o null>,
  "safety_stop_m": <número (profundidad de la parada de seguridad) o null>,
  "deco_stop_m": <número (profundidad de la parada de descompresión, si la hay) o null>,
  "dive_center": "<texto o null — centro de buceo>",
  "dive_club": "<texto o null — club de buceo>",
  "notes": "<texto o null — observaciones/comentarios de la propia hoja, resumidos>"
}

Para los campos de texto, respeta el idioma original de la hoja. Para approach_type/seabed_type/air_type/suit_type/tank_material/current, traduce el concepto al español y elige EXACTAMENTE una de las opciones dadas (o null si no encaja ninguna con confianza) — nunca inventes una opción fuera de esa lista.`;

  let geminiRes: Response;
  try {
    geminiRes = await fetch(`${GEMINI_URL}?key=${GEMINI_API_KEY}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        contents: [
          {
            parts: [
              { text: prompt },
              { inline_data: { mime_type: mimeType || "image/jpeg", data: imageBase64 } },
            ],
          },
        ],
        generationConfig: { temperature: 0, responseMimeType: "application/json" },
      }),
    });
  } catch (e) {
    return json({ error: "No se pudo contactar con Gemini", detail: String(e) }, 502);
  }

  if (!geminiRes.ok) {
    const detail = await geminiRes.text();
    return json({ error: "Gemini devolvió un error", detail }, 502);
  }

  const data = await geminiRes.json();
  const text: string = data?.candidates?.[0]?.content?.parts?.[0]?.text ?? "{}";

  // deno-lint-ignore no-explicit-any
  let parsed: Record<string, any>;
  try {
    parsed = JSON.parse(text);
  } catch {
    return json({ error: "Respuesta de Gemini no interpretable" }, 502);
  }

  const result: Record<string, unknown> = {};

  for (const key of NUMBER_FIELDS) {
    const v = parsed[key];
    result[key] = typeof v === "number" && Number.isFinite(v) ? v : null;
  }
  for (const key of TEXT_FIELDS) {
    const v = parsed[key];
    result[key] = typeof v === "string" && v.trim() ? v.trim() : null;
  }
  result.date = typeof parsed.date === "string" && /^\d{4}-\d{2}-\d{2}$/.test(parsed.date) ? parsed.date : null;
  result.entry_time = padTime(parsed.entry_time);
  result.exit_time = padTime(parsed.exit_time);
  result.approach_type = APPROACH_OPTIONS.includes(parsed.approach_type) ? parsed.approach_type : null;
  result.seabed_type = SEABED_OPTIONS.includes(parsed.seabed_type) ? parsed.seabed_type : null;
  result.air_type = AIR_TYPE_OPTIONS.includes(parsed.air_type) ? parsed.air_type : null;
  result.suit_type = SUIT_OPTIONS.includes(parsed.suit_type) ? parsed.suit_type : null;
  result.tank_material = TANK_MATERIAL_OPTIONS.includes(parsed.tank_material) ? parsed.tank_material : null;
  result.current = CURRENT_OPTIONS.includes(parsed.current) ? parsed.current : null;

  return json(result);
});
