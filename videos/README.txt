Videos del hero de landing.html
================================

Para que las dos animaciones de la sección "quién es el protagonista" dejen
de mostrar el placeholder y reproduzcan tu vídeo real, basta con dejar aquí
dos archivos con EXACTAMENTE estos nombres. No hace falta tocar ni una línea
de código: landing.html ya los busca en esta carpeta y, si no los encuentra,
sigue mostrando el placeholder de texto sin ningún error.

1) videos/laptop-screen.mp4
   - Lo que se ve dentro de la pantalla del portátil.
   - Relación de aspecto: 16:9 (igual que el marco que lo contiene).
   - Recomendado: 1280x720 o 1920x1080.

2) videos/phone-screen.mp4
   - Lo que se ve dentro de la pantalla del móvil.
   - Relación de aspecto: 9:18.5 (igual que el marco que lo contiene).
   - Recomendado: 886x1820 o similar (ancho x alto, vertical).

Formato: MP4 con códec de vídeo H.264 (el más compatible en navegadores).
El audio no importa: los vídeos se reproducen siempre en mute (autoplay
muted loop), así que puedes exportarlos sin pista de audio.

El vídeo se recorta con object-fit:cover para llenar el marco por completo,
así que no hace falta que la resolución sea exacta, solo que la relación de
aspecto (16:9 o 9:18.5) sea parecida para que no se vea recortado de forma
rara.
