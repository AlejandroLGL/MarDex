// MarDex Service Worker
// Estrategia: cache-first para el shell de la app, network-first para imágenes

const CACHE_NAME = 'mardex-v4';
const CACHE_DURATION_IMAGES = 30 * 24 * 60 * 60 * 1000; // 30 días

// Recursos del shell de la app que se cachean en la instalación
const SHELL_ASSETS = [
  './index.html',
  './manifest.json',
  './icon-192.png',
  './icon-512.png',
  './apple-touch-icon.png',
];

// ── Install: pre-cachear el shell ─────────────────────────────────────────
self.addEventListener('install', event => {
  event.waitUntil(
    caches.open(CACHE_NAME).then(cache => cache.addAll(SHELL_ASSETS))
  );
  self.skipWaiting();
});

// ── Activate: limpiar cachés antiguas ─────────────────────────────────────
self.addEventListener('activate', event => {
  event.waitUntil(
    caches.keys().then(keys =>
      Promise.all(keys.filter(k => k !== CACHE_NAME).map(k => caches.delete(k)))
    )
  );
  self.clients.claim();
});

// ── Fetch ─────────────────────────────────────────────────────────────────
self.addEventListener('fetch', event => {
  const url = new URL(event.request.url);

  // CDN externas (Leaflet, Google Fonts) → network-first, cache como fallback
  if (url.origin !== location.origin) {
    event.respondWith(networkFirstStrategy(event.request));
    return;
  }

  // Imágenes de especies → cache-first (son grandes y no cambian)
  if (url.pathname.includes('/especies/imagenes/')) {
    event.respondWith(cacheFirstStrategy(event.request));
    return;
  }

  // Imágenes de fondo → cache-first
  if (url.pathname.includes('/background_images/')) {
    event.respondWith(cacheFirstStrategy(event.request));
    return;
  }

  // Catálogo de especies → network-first (cambia con cada especie añadida;
  // preferimos datos frescos y solo caemos al caché si no hay conexión)
  if (url.pathname.endsWith('/species.json')) {
    event.respondWith(networkFirstStrategy(event.request));
    return;
  }

  // Shell HTML/manifest → network-first: la app cambia con cada despliegue,
  // así que si hay conexión queremos siempre la versión nueva y solo caemos
  // al caché cuando no hay red (antes esto iba por stale-while-revalidate,
  // que enseña primero lo que hubiera cacheado en el install y podía dejar
  // a un dispositivo viendo una versión muy vieja de la app indefinidamente).
  if (url.pathname.endsWith('/index.html') || url.pathname === '/' || url.pathname.endsWith('/manifest.json')) {
    event.respondWith(networkFirstStrategy(event.request));
    return;
  }

  // Resto del shell (iconos) → stale-while-revalidate
  event.respondWith(staleWhileRevalidate(event.request));
});

// ── Estrategias de caché ──────────────────────────────────────────────────

async function cacheFirstStrategy(request) {
  const cached = await caches.match(request);
  if (cached) return cached;
  try {
    // cache:'reload' ignora la caché HTTP del dispositivo para esta petición,
    // así una foto que antes daba 404 (porque aún no existía) no se queda
    // pegada indefinidamente aunque ya esté disponible en el servidor.
    const response = await fetch(request, { cache: 'reload' });
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    return new Response('Sin conexión', { status: 503 });
  }
}

async function networkFirstStrategy(request) {
  try {
    const response = await fetch(request);
    if (response.ok) {
      const cache = await caches.open(CACHE_NAME);
      cache.put(request, response.clone());
    }
    return response;
  } catch {
    const cached = await caches.match(request);
    return cached || new Response('Sin conexión', { status: 503 });
  }
}

async function staleWhileRevalidate(request) {
  const cache = await caches.open(CACHE_NAME);
  const cached = await cache.match(request);
  const fetchPromise = fetch(request).then(response => {
    if (response.ok) cache.put(request, response.clone());
    return response;
  }).catch(() => null);
  return cached || await fetchPromise || new Response('Sin conexión', { status: 503 });
}
