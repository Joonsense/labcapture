# LabCapture

[English](README.md) | [한국어](README.ko.md) | [简体中文](README.zh-CN.md) | [日本語](README.ja.md) | **Español**

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-black?logo=apple) ![Swift](https://img.shields.io/badge/Swift-5.9-orange?logo=swift) ![License: MIT](https://img.shields.io/badge/License-MIT-green) ![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen)

**Construye en público, sin interrumpir tu flujo.**

LabCapture es una pequeña aplicación de barra de menú de macOS que registra automáticamente tu pantalla + cámara web durante ~3 segundos mientras trabajas, y convierte el metraje en contenido listo para publicar: GIFs, un timelapse diario de alta calidad con cámara facial circular, y un diario de construcción escrito por IA.

Tú construyes. Eso captura. Al final del día tendrás un timelapse de 1080p de tu sesión de trabajo, GIFs listos para compartir, y un diario Markdown de lo que hiciste — todo generado en tu máquina.

## Qué obtienes

Cada captura (por defecto: cada 20 minutos, más en cada `git push`) produce archivos nombrados `YYYY-MM-DD_HHmmss_*`:

- `*_screen.gif` — tu pantalla (960px de ancho, con marca de tiempo)
- `*_face.gif` — tu cámara web
- `*_combo.gif` — pantalla con una **cámara facial circular** superpuesta (anillo lima, picture-in-picture)
- `*_screen.mp4` / `*_face.mp4` — originales de alta calidad (CRF 18, 30 fps)

Y una vez al día (un clic o una llamada API):

- **Timelapse** — todas las capturas de hoy cosidas en un MP4 de 1080p/30fps: tu pantalla como fondo, tu cara como un círculo en el centro, marcas de tiempo por segmento
- **Diario de construcción** — Claude lee tu manifiesto de capturas + fotogramas clave y escribe `summary.md`: un resumen de una línea, una cronología de lo que trabajaste, y 1-2 publicaciones sugeridas para X/Twitter
- **Asistente del portapapeles** — copia la última captura y ⌘V directamente en una publicación

## Privacidad y seguridad primero

Esta es una herramienta que registra tu pantalla, así que está diseñada para ser paranoica:

- **100% local.** Sin cuentas, sin telemetría, sin descargas. Los archivos solo existen en `~/LabCapture` en tu máquina. La única llamada de red opcional es el diario de construcción, que envía datos a la API de Claude *solo cuando lo activas*.
- **Guardián de secretos (OCR).** Justo después de cada grabación, Apple Vision OCR escanea los fotogramas. Si una clave API, token, contraseña o cadena de conexión de BD es visible en la pantalla, la **captura completa se descarta** y se reintenta. Tres descartes consecutivos pausan la captura durante horas (configurable). Patrones cubiertos: claves `sk-...`, GitHub PATs, claves AWS, tokens Slack/Notion, JWTs, bloques PRIVATE KEY, tokens Bearer, asignaciones `API_KEY=` env, y más — coincidencia flexible a propósito, porque la sobre-detección es la dirección segura.
- **Advertencia previa a la captura.** Una notificación opcional se dispara unos segundos antes de cada captura para que nunca seas grabado por sorpresa.
- **Botones de parada en todas partes.** Alterna fuentes de pantalla/cara independientemente desde la barra de menú (o API), pausa por una hora / por hoy / en un horario nocturno. Las capturas se saltan automáticamente mientras tu pantalla está bloqueada o dormida.
- **Nada se compromete nunca.** El `.gitignore` del repositorio bloquea todos los archivos multimedia, y tu carpeta de salida vive fuera del repositorio.

## Requisitos

- macOS 14+ (Apple Silicon)
- ffmpeg: `brew install ffmpeg`
- Herramientas de línea de comandos de Xcode (para compilar): `xcode-select --install`

## Instalar

```bash
git clone https://github.com/Joonsense/labcapture.git
cd labcapture
./build.sh
open dist/LabCapture.app
```

En el primer lanzamiento, una ventana de incorporación te guía a través de los dos permisos que necesita:

| Permiso | Dónde | Usado para |
|---|---|---|
| Screen Recording | System Settings → Privacy & Security | captura de pantalla (proceso hijo ffmpeg) |
| Camera | System Settings → Privacy & Security | captura de cámara web |

Consejos:

- Otorga permisos mientras ejecutas el `dist/LabCapture.app` compilado (no un compilado de terminal) — TCC los rastrea por separado.
- Si las capturas fallan y el botón *parece* habilitado, el registro de permisos está obsoleto: `tccutil reset ScreenCapture com.deblockx.labcapture`, luego vuelve a otorgar. Consulta [docs/SIGNING.md](docs/SIGNING.md) para saber cómo crear un certificado de firma local para que los permisos **sobrevivan a las recompilaciones** (recomendado si modificas el código fuente).
- Sin permisos, las capturas se saltan con gracia con una notificación — sin bloqueos.

## Uso

- **Automático** — capturas cada 20 minutos por defecto (5-120 min configurables)
- **Barra de menú** — capturar ahora / pausar (1 h, hoy) / revelar última captura / abrir carpeta de hoy / configuración
- **Tecla de acceso rápido global** — `⌃⌥⌘C` por defecto (rebindable)
- **Horas silenciosas** — p. ej. pausar capturas de temporizador 21:00-09:00 (captura manual aún funciona)
- Auto-salta mientras está bloqueado/dormido, y cuando el espacio en disco libre cae por debajo de 500 MB

### Icono de la barra de menú

Dos formas: **rectángulo = fuente de pantalla, círculo = fuente de cara**. Relleno = activado, delineado + barra = desactivado. El color muestra el estado general: 🟢 lima activo · ⚪ gris pausado · 🔴 rojo capturando · 🟠 naranja última captura falló.

## Diseño de salida

```
~/LabCapture/
  2026-06-12/
    2026-06-12_143012_screen.gif
    2026-06-12_143012_face.gif
    2026-06-12_143012_combo.gif
    2026-06-12_143012_screen.mp4     ← cuando "keep originals" está activado (por defecto)
    2026-06-12_143012_face.mp4
    timelapse_2026-06-12_213000.mp4  ← timelapse diario
    summary.md                       ← diario de construcción AI
    manifest.jsonl                   ← una línea JSON por captura
  labcapture.log
```

## API HTTP — construida para humanos *y* agentes IA

La aplicación escucha en `http://127.0.0.1:48620` (solo loopback, nunca expuesto). **Un agente LLM puede descubrir toda la API desde una única llamada a `GET /capabilities`** — devuelve una especificación legible por máquina.

| Método | Ruta | Acción |
|---|---|---|
| GET | `/capabilities` | especificación API legible por máquina |
| GET | `/status` | estado (`active/paused/capturing/warning`), fuentes, próxima captura, último error/archivo |
| POST | `/capture` | capturar ahora (202; 409 si está ocupado). `GET/POST /trigger` es un alias para git hooks |
| POST | `/source/screen/on` · `/off` | alternar fuente de pantalla |
| POST | `/source/face/on` · `/off` | alternar cara (cámara web) |
| POST | `/pause` · `/pause/today` · `/resume` | pausar 1 h / hasta medianoche / reanudar |
| POST | `/last/copy` | copiar último combo.gif al portapapeles (⌘V en X) |
| POST | `/timelapse` | compilar originales de hoy en el timelapse 1080p (202) |
| POST | `/summary` | generar diario de construcción AI de hoy (202; 400 sin clave API) |

```bash
curl -s http://127.0.0.1:48620/status | jq .sources
curl -s -X POST http://127.0.0.1:48620/source/face/off   # capturas solo de pantalla
curl -s -X POST http://127.0.0.1:48620/capture
```

### Capturar en cada git push

```bash
# <tu-repositorio>/.git/hooks/pre-push  (chmod +x)
#!/bin/sh
curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null 2>&1 || true
exit 0
```

O como un alias global que se dispara justo después de un push exitoso:

```bash
git config --global alias.pushc '!git push "$@" && curl -s -m 2 http://127.0.0.1:48620/trigger >/dev/null; true'
```

## Diario de construcción AI (opcional)

Establece una clave API de Claude (nunca codificada — archivo o variable env):

```bash
mkdir -p ~/.config/labcapture && printf '%s' 'sk-ant-...' > ~/.config/labcapture/anthropic_api_key && chmod 600 ~/.config/labcapture/anthropic_api_key
```

Luego "Daily wrap-up" en el menú (o `POST /summary`) envía `manifest.jsonl` + hasta 6 fotogramas representativos a Claude y escribe `summary.md`: resumen de una línea, cronología de trabajo, y publicaciones X sugeridas basadas en lo que es realmente visible en tus capturas.

## Configuración

| Configuración | Defecto | Rango |
|---|---|---|
| Intervalo de captura | 20 min | 5-120 |
| Duración de captura | 3 s | 1-5 |
| Notificación previa a captura / tiempo de anticipación | activado / 3 s | 0-10 s |
| Captura de cámara web | activado | desactivado → solo pantalla |
| Posición PiP (GIF combo) | abajo-derecha | tl / tr / bl / br |
| GIF fps | 15 | 8-15 |
| Ancho GIF de pantalla | 960 px | 480-1080 |
| Carpeta de salida | `~/LabCapture` | cualquiera |
| Mantener mp4s originales | activado | desactivado → timelapse se retrocede a GIFs (baja calidad) |
| Horas silenciosas | desactivado | hora de inicio/fin |
| Tecla de acceso rápido global | ⌃⌥⌘C | rebindable |
| Guardián de secretos (OCR) | activado | pausar 1-12 h después de 3 descartes |

Todas las configuraciones persisten a través de `UserDefaults`.

## Esquema manifest.jsonl (entrada de canalización LLM)

Una línea JSON por captura, `schema: 1`:

```json
{"schema":1,"ts":"2026-06-12T18:25:23+09:00","trigger":"push","duration":3,
 "sources":["screen","face"],
 "files":["2026-06-12_182523_screen.gif","2026-06-12_182523_face.gif","2026-06-12_182523_combo.gif"],
 "kinds":{"2026-06-12_182523_screen.gif":"screen","2026-06-12_182523_face.gif":"face","2026-06-12_182523_combo.gif":"combo"}}
```

`trigger`: `timer` / `manual` / `hotkey` / `push` (git integration)

## Arquitectura

Una aplicación de barra de menú Swift/SwiftUI orquesta; la grabación/codificación se delega a subprocesos ffmpeg.

```
Sources/LabCapture/
  LabCaptureApp.swift    entrada (MenuBarExtra + Settings scene)
  AppModel.swift         estado central: temporizador/pausa/detección de bloqueo/registro de errores/incorporación
  CaptureEngine.swift    grabar → 3 GIFs → manifiesto (canalización principal)
  DailyPipeline.swift    timelapse + diario Claude + asistente de portapapeles
  FFmpeg.swift           ejecutor de proceso ffmpeg + detección de dispositivo avfoundation
  OCRGuard.swift         detección de secretos de Vision OCR
  TriggerServer.swift    servidor HTTP 127.0.0.1:48620
  HotkeyManager.swift    tecla de acceso rápido global Carbon
  Permissions.swift      comprobaciones de TCC / enlaces profundos de configuración
  Views/                 UI de menú / configuración / incorporación
```

Detalles de codificación: paleta GIF de dos pasadas (`palettegen stats_mode=diff` → `paletteuse` sierra2_4a dithering); máscara de cara circular vía `geq` alfa con borde atenuado; segmentos de timelapse normalizados a 1080p/30fps luego concatenados sin pérdida; marcas de tiempo vía `drawtext` + `textfile=` (evita el escape de dos puntos de filtergraph).

## Solución de problemas

- **"Configuration of video device failed"** mientras el botón Screen Recording parece ACTIVADO → registro TCC obsoleto (la aplicación fue re-firmada). Solución: `tccutil reset ScreenCapture com.deblockx.labcapture`, reinicia, vuelve a otorgar. Prevénlo permanentemente con un [certificado de firma local](docs/SIGNING.md).
- **ffmpeg no encontrado** → `brew install ffmpeg` (esperado en `/opt/homebrew/bin/ffmpeg`).
- Los errores se registran en `~/LabCapture/labcapture.log` (también visible desde el menú).

## Hoja de ruta

- Agrupación ffmpeg (instalación sin dependencias)
- Versiones notarizadas
- Selección de múltiples monitores (actualmente pantalla principal)
- Soporte para Mac Intel

PRs bienvenidas.

## Licencia

[MIT](LICENSE) © DeblockX Labs
