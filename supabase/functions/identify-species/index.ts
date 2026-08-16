// Identifica la especie de MarDex más probable a partir de una foto,
// usando Gemini (Google AI Studio). La API key vive solo aquí, como
// secreto de Supabase — nunca se expone al cliente.
//
// Body esperado (JSON):
//   { imageBase64: string, mimeType?: string, species: {id, name, sci}[] }
// Respuesta (JSON):
//   { id: string|null, confidence: "alta"|"media"|"baja", note: string }

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

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });
  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!GEMINI_API_KEY) return json({ error: "Falta GEMINI_API_KEY en los secretos de Supabase" }, 500);

  let body: { imageBase64?: string; mimeType?: string; species?: { id: string; name: string; sci: string }[] };
  try {
    body = await req.json();
  } catch {
    return json({ error: "Body no es JSON válido" }, 400);
  }

  const { imageBase64, mimeType, species } = body;
  if (!imageBase64 || !Array.isArray(species) || species.length === 0) {
    return json({ error: "Faltan imageBase64 o species" }, 400);
  }

  const catalog = species.map((s) => `- id:"${s.id}" | ${s.name} (${s.sci})`).join("\n");
  const prompt = `Eres un experto en biología marina ayudando a un buceador a identificar lo que ha fotografiado.

Catálogo de especies disponibles en la app (solo puedes elegir un id de esta lista, o null):
${catalog}

Analiza la foto adjunta y responde ÚNICAMENTE con un JSON con este formato exacto, sin texto adicional ni bloques de código:
{"id": "id_de_la_especie_o_null", "confidence": "alta|media|baja", "note": "breve razón en español, máximo 20 palabras"}

Si la foto no muestra con claridad ninguna especie del catálogo, o no es un animal marino, devuelve "id": null.`;

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

  let parsed: { id: string | null; confidence?: string; note?: string };
  try {
    parsed = JSON.parse(text);
  } catch {
    parsed = { id: null, confidence: "baja", note: "Respuesta no interpretable" };
  }

  const validIds = new Set(species.map((s) => s.id));
  if (parsed.id && !validIds.has(parsed.id)) parsed.id = null;

  return json(parsed);
});
