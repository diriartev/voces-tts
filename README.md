# 🎙️ Voces TTS — Generador de Voz en Español + Voces Clonadas (RVC)

Generador de voces en español con interfaz web. Trae voces neuronales normales y **voces clonadas con RVC** (incluye Spider-Man de Tobey Maguire y de PS4), todo dentro de un contenedor Docker endurecido. Se instala con **un solo comando**.

| Voz | Tipo | Tiempo aprox. |
| --- | --- | --- |
| 🎙️ Voz Custom | Profunda y cinematográfica (EQ + eco) | ~1–2 s |
| 🎙️ Narrador Latino Neutro | Natural, estilo documental | ~1–2 s |
| 🇨🇴 Narrador Colombiano | Cálida y nítida | ~1–2 s |
| 🇪🇸 Narrador España | Castellano moderno | ~1–2 s |
| 🕷️ Spider-Man (Tobey Maguire) | Clonada con RVC | ~5–25 s (CPU) |
| 🕷️ Spider-Man (PS4) | Clonada con RVC | ~5–25 s (CPU) |

- ⏩ Control de velocidad y nombre personalizado del archivo
- 📂 Cargar texto desde cualquier `.txt`
- 🎭 **Añade tus propias voces RVC** metiendo una carpeta con su `.pth` (ver [`modelos_rvc/LEEME.md`](modelos_rvc/LEEME.md))
- 💾 **Tú eliges dónde guardar** cada audio con "Guardar como" (Chrome/Edge/Brave/Opera; en Firefox, activa "Preguntar siempre dónde guardar")
- 🛡️ Los audios se generan **solo en RAM** y se borran solos (30 min o al apagar); nada se guarda en tu disco salvo lo que tú elijas
- 🚀 Cero consumo en reposo: se apaga por completo con `bash detener.sh`

## 🚀 Instalación (plug and play)

Requisitos: Linux con **Docker** y **Docker Compose**, más `curl` y `python3`. Unos **6 GB** libres en disco y 4 GB de RAM. No necesita GPU.

```bash
# Desde GitHub
git clone https://github.com/diriartev/voces-tts.git
cd voces-tts
bash iniciar.sh
```

`iniciar.sh` hace todo solo:

1. Comprueba Docker (usa `sudo` si hace falta) y crea el `.env` con tu UID/GID.
2. Instala los modelos de voz y **verifica su SHA-256**:
   - si los `.zip` de los modelos están en la carpeta, los usa sin internet;
   - si no, los baja del Release `modelos-v1` de `diriartev/voces-tts`.
3. Construye la imagen. La primera vez tarda varios minutos porque baja PyTorch CPU y los modelos base de RVC.
4. Arranca y abre **http://127.0.0.1:5055**.

### Sin GitHub (pasándolo en zip)

```bash
unzip voces-tts-con-modelos.zip
cd voces-tts
bash iniciar.sh
```

El paquete `voces-tts-con-modelos.zip` ya trae dentro los zips de los modelos (`spiderman_tobey.zip`, `spiderman_ps4.zip`) y los instala sin internet. Si tienes la versión sin modelos, copia esos dos zips en la carpeta `voces-tts/`, junto a `iniciar.sh`. Si faltan, las voces normales funcionan igual.

## 🛠️ Comandos

```bash
bash iniciar.sh                  # modelos + construir + arrancar + abrir web
bash estado.sh                   # ¿está encendido? ¿cuántas voces RVC cargó?
bash detener.sh                  # apagar y liberar toda la RAM/CPU
bash descargar_modelos.sh        # solo instalar/verificar modelos

docker compose logs -f           # logs en vivo
docker compose build --no-cache  # reconstruir desde cero
docker compose down --rmi local  # borrar contenedor e imagen
```

Configuración: el `.env` se crea en el primer arranque (puerto, núcleos de CPU para RVC, repo de modelos).

## 🩺 Problemas comunes

| Síntoma | Solución |
| --- | --- |
| `permission denied ... docker.sock` | `sudo usermod -aG docker $USER` y cierra/abre sesión (o deja que el script use sudo) |
| `docker: 'compose' is not a docker command` | `sudo apt install docker-compose-plugin` (o `docker-compose-v2`) |
| `port is already allocated` | Cambia `PORT=` en `.env` |
| No salen las voces de Spider-Man | `bash descargar_modelos.sh` y mira el error; luego `bash detener.sh && bash iniciar.sh` |
| La voz RVC tarda mucho | Normal en CPU (~5–25 s; la primera vez tarda más porque carga el motor). Sube `CPUS=` en `.env` |

## 🛡️ Seguridad

- Corre con tu propio UID (nunca root), con `cap_drop: ALL` y `no-new-privileges`
- Sistema de archivos `read_only`; los modelos se montan en **solo lectura**
- Publicado solo en `127.0.0.1` (no visible en tu red ni en internet)
- Límites de CPU, RAM (4 GB) y procesos
- Los modelos descargados se verifican con **SHA-256** (`modelos_rvc/checksums.sha256`) y del zip solo se extraen `.pth`/`.index`
- Las dependencias de Python están fijadas a versiones exactas (`requirements.txt`) y PyTorch está en 2.11 (sin la vulnerabilidad crítica CVE-2025-32434)
- Los modelos de voz `.pth` se cargan en **modo seguro** (`weights_only=True`): un modelo malicioso no puede ejecutar código. Hay una prueba automática que lo comprueba
- Los modelos base de RVC (HuBERT, RMVPE) se verifican por **SHA-256** al construir la imagen

> ℹ️ El texto se sintetiza primero con [edge-tts](https://github.com/rany2/edge-tts), que lo envía al servicio de voz de Microsoft Edge. Necesita internet y no conviene usarlo con textos confidenciales. La conversión RVC sí es 100 % local.

## 🔌 API

| Método | Ruta | Descripción |
| --- | --- | --- |
| GET | `/health` | Estado del servicio y nº de voces RVC |
| GET | `/api/voices` | Lista de voces |
| POST | `/api/synthesize` | `{"text": "...", "voice": "rvc-spiderman_tobey", "speed": 1.0, "name": "opcional"}` |
| GET | `/audio/<archivo>.wav` | Reproducir (`?download=1` para descargar) |

```bash
curl -s -X POST http://127.0.0.1:5055/api/synthesize \
  -H 'Content-Type: application/json' \
  -d '{"text":"Un gran poder conlleva una gran responsabilidad","voice":"rvc-spiderman_tobey"}'
```

## 🔄 CI/CD (pruebas y publicación automáticas)

Este repo usa [CI Seguro](https://github.com/diriartev/ci-seguro), el pipeline universal de todos mis repos. Cada cambio pasa por el mismo motor (`ci/revisar.sh`), **en tu PC y en GitHub**:

| Etapa | Herramienta | Qué detiene |
| --- | --- | --- |
| 1 · Secretos | gitleaks (todo el historial) | llaves, tokens, contraseñas, aunque se hayan borrado después |
| 2 · Código | ruff + bandit, shellcheck, hadolint, actionlint | bugs y patrones inseguros en Python, Bash, Dockerfile y workflows; acciones sin fijar por hash |
| 3 · Configuración | trivy config | contenedores mal configurados |
| 4 · Dependencias | trivy fs | librerías con vulnerabilidades **críticas** que ya tienen parche |
| 5 · Build | Docker | que la imagen no construya |
| 6 · Pruebas | `ci/pruebas.sh` contra el contenedor endurecido real | funciones rotas y regresiones de seguridad |
| 7 · Vulnerabilidades | trivy image | vulnerabilidades **críticas** con parche disponible |

```bash
bash ci/revisar.sh                # todo el pipeline en local (atajo: bash probar.sh)
bash ci/revisar.sh secretos lint  # solo lo rápido
```

**Publicar una versión** (semi-automático):

```bash
git tag -s v1.0.0 -m "v1.0.0"
git push origin v1.0.0
```

GitHub repite todo el CI y **espera tu aprobación** (Actions → *Review deployments*). Después publica la imagen firmada en `ghcr.io`, con SBOM y certificado de procedencia, y crea el Release.

**Usar la imagen publicada** en vez de construirla: en `.env` descomenta `IMAGE=ghcr.io/...:latest` y ejecuta `bash iniciar.sh`. Si tienes [cosign](https://docs.sigstore.dev/cosign/system_config/installation/), verifica la firma automáticamente.

## 📁 Estructura

```
.
├── Dockerfile               # python 3.10 + PyTorch 2.11 CPU + rvc-python + edge-tts
├── docker-compose.yml       # Despliegue endurecido
├── requirements*.txt        # Dependencias con versiones fijas
├── patch_rvc.py             # Adapta rvc-python para correr sin root y en solo lectura
├── server.py                # Backend (aiohttp)
├── public/index.html        # Interfaz web
├── modelos_rvc/             # Una carpeta por voz (los .pth/.index se descargan solos)
│   ├── LEEME.md             # Cómo añadir tus propias voces
│   ├── checksums.sha256
│   ├── spiderman_tobey/voz.json
│   └── spiderman_ps4/voz.json
├── _comun.sh                # Detecta Docker/sudo/compose y prepara .env
├── probar.sh                # Atajo a ci/revisar.sh
├── ci/                      # revisar.sh (motor CI Seguro), pruebas.sh (pruebas de este repo)
├── tests/                   # Pruebas de funcionamiento, seguridad y modelos maliciosos
├── ruff.toml                # Reglas del linter de Python (bugs + seguridad)
├── SECURITY.md              # Cómo reportar vulnerabilidades
├── .github/workflows/       # ci.yml (cada push) y release.yml (publicar versión)
├── .github/dependabot.yml
└── *.sh                     # iniciar / detener / estado / descargar_modelos
```

## 📦 Releases Modelos

Los modelos pesan demasiado para guardarlos en git (GitHub limita a 100 MB por archivo), así que van como archivos de un **Release**:

## ⚖️ Aviso

Proyecto personal y sin ánimo de lucro. Los modelos de voz son creaciones de fans que imitan a personajes y actores reales; sus derechos pertenecen a sus dueños. No uses las voces clonadas para suplantar a nadie, engañar o hacer contenido que pueda confundirse con declaraciones reales.
