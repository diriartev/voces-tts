#!/usr/bin/env python3
"""
Generador de Voz Español - Servidor de Voz en Memoria RAM
"""

import os
import json
import asyncio
import logging
import time
import glob
import threading
from aiohttp import web
import edge_tts

# Logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("voces-tts")

PORT = int(os.environ.get("PORT", 5055))
BASE_DIR = os.path.dirname(os.path.abspath(__file__))
PUBLIC_DIR = os.path.join(BASE_DIR, "public")
PREVIEWS_DIR = os.environ.get("PREVIEWS_DIR", "/tmp/previews")  # noqa: S108 - tmpfs privado del contenedor
MODELS_DIR = os.environ.get("MODELS_DIR", os.path.join(BASE_DIR, "modelos_rvc"))

# Catálogo oficial
VOICES = [
    {
        "id": "voz-custom",
        "name": "🎙️ Voz Custom",
        "desc": "Voz profunda, imponente y cinematográfica en español",
        "voice": "es-MX-JorgeNeural",
        "pitch": "-14Hz",
        "rate": "-5%",
        "filter": "equalizer=f=110:t=q:w=1:g=7,equalizer=f=3000:t=q:w=1:g=2,aecho=0.8:0.6:16:0.25,volume=1.3"
    },
    {
        "id": "latino-neutro",
        "name": "🎙️ Narrador Latino Neutro (Profesional)",
        "desc": "Voz documental / YouTube clara y natural de alta fidelidad",
        "voice": "es-MX-JorgeNeural",
        "pitch": "+0Hz",
        "rate": "+0%",
        "filter": "volume=1.2"
    },
    {
        "id": "colombiano",
        "name": "🇨🇴 Narrador Colombiano",
        "desc": "Voz en español de Colombia cálida y nítida",
        "voice": "es-CO-GonzaloNeural",
        "pitch": "+0Hz",
        "rate": "+0%",
        "filter": "volume=1.2"
    },
    {
        "id": "espana",
        "name": "🇪🇸 Narrador España (Castellano)",
        "desc": "Voz castellana moderna y profesional",
        "voice": "es-ES-AlvaroNeural",
        "pitch": "+0Hz",
        "rate": "+0%",
        "filter": "volume=1.2"
    }
]

# ------------------------------------------------------------------
# Voces RVC (clonación): cada carpeta en modelos_rvc/ con un .pth es una voz.
# Opcional: un voz.json en la carpeta con nombre, descripción y ajustes.
# ------------------------------------------------------------------
def load_rvc_voices():
    voices = []
    for d in sorted(glob.glob(os.path.join(MODELS_DIR, "*"))):
        if not os.path.isdir(d):
            continue
        pth = glob.glob(os.path.join(d, "*.pth"))
        if not pth:
            continue
        idx = glob.glob(os.path.join(d, "*.index"))
        folder = os.path.basename(d)
        cfg = {}
        cfg_path = os.path.join(d, "voz.json")
        if os.path.isfile(cfg_path):
            try:
                with open(cfg_path, encoding="utf-8") as f:
                    cfg = json.load(f)
            except Exception as e:
                logger.warning(f"voz.json inválido en {folder}: {e}")
        voices.append({
            "id": f"rvc-{folder}",
            "name": cfg.get("name", f"🎭 {folder}"),
            "desc": cfg.get("desc", "Voz clonada con RVC (tarda unos segundos más)"),
            "voice": cfg.get("base_voice", "es-MX-JorgeNeural"),
            "pitch": cfg.get("base_pitch", "+0Hz"),
            "rate": cfg.get("base_rate", "+0%"),
            "filter": cfg.get("filter", "volume=1.2"),
            "rvc": {
                "pth": pth[0],
                "index": idx[0] if idx else "",
                "f0up_key": int(cfg.get("f0up_key", 0)),
                "index_rate": float(cfg.get("index_rate", 0.6)),
                "protect": float(cfg.get("protect", 0.33)),
            },
        })
    return voices

RVC_VOICES = load_rvc_voices()
VOICES = VOICES + RVC_VOICES
VOICE_MAP = {v["id"]: v for v in VOICES}

# Motor RVC: se carga solo la primera vez que alguien usa una voz RVC
_rvc_engine = None
_rvc_loaded = None
_rvc_lock = threading.Lock()

def rvc_convert(cfg, in_wav, out_wav):
    """Convierte in_wav a la voz del modelo (bloqueante, se ejecuta en un hilo)."""
    global _rvc_engine, _rvc_loaded
    with _rvc_lock:
        if _rvc_engine is None:
            from rvc_python.infer import RVCInference
            logger.info("Cargando motor RVC (solo la primera vez)...")
            _rvc_engine = RVCInference(device="cpu:0", models_dir=MODELS_DIR)
        if _rvc_loaded != cfg["pth"]:
            _rvc_engine.load_model(cfg["pth"], index_path=cfg["index"])
            _rvc_loaded = cfg["pth"]
        _rvc_engine.set_params(
            f0up_key=cfg["f0up_key"], f0method="rmvpe",
            index_rate=cfg["index_rate"], protect=cfg["protect"],
        )
        _rvc_engine.infer_file(in_wav, out_wav)

def public_voice(v):
    return {k: v[k] for k in ("id", "name", "desc")}

def cleanup_old_previews():
    now = time.time()
    try:
        if os.path.exists(PREVIEWS_DIR):
            for f in os.listdir(PREVIEWS_DIR):
                f_path = os.path.join(PREVIEWS_DIR, f)
                if os.path.isfile(f_path) and (now - os.path.getmtime(f_path) > 1800):
                    os.remove(f_path)
    except Exception as e:
        logger.warning(f"Error en limpieza de preview: {e}")

async def handle_index(request):
    return web.FileResponse(os.path.join(PUBLIC_DIR, "index.html"))

async def handle_health(request):
    return web.json_response({
        "status": "ok",
        "service": "generador-de-voz-espanol",
        "version": "7.0.0",
        "rvc_voices": len(RVC_VOICES)
    })

async def handle_voices(request):
    return web.json_response({"voices": [public_voice(v) for v in VOICES]})

async def handle_audio(request):
    filename = request.match_info.get("filename", "")
    safe_name = os.path.basename(filename)
    path = os.path.join(PREVIEWS_DIR, safe_name)
    if not os.path.isfile(path):
        return web.Response(status=404, text="Audio no encontrado o expirado")
    
    is_download = request.query.get("download") == "1"
    disposition = f'attachment; filename="{safe_name}"' if is_download else f'inline; filename="{safe_name}"'
    return web.FileResponse(path, headers={"Content-Disposition": disposition})

async def handle_synthesize(request):
    try:
        data = await request.json()
    except:
        return web.json_response({"success": False, "error": "JSON inválido"}, status=400)

    text = data.get("text", "").strip()
    voice_id = data.get("voice", "voz-custom")
    try:
        speed_mult = min(max(float(data.get("speed", 1.0)), 0.5), 2.0)
    except (TypeError, ValueError):
        speed_mult = 1.0
    custom_name = data.get("name", "").strip()

    if not text:
        return web.json_response({"success": False, "error": "El texto está vacío."}, status=400)
    if len(text) > 5000:
        return web.json_response({"success": False, "error": "Máximo 5000 caracteres por audio."}, status=400)

    prof = VOICE_MAP.get(voice_id, VOICES[0])
    cleanup_old_previews()

    base_rate = int(prof["rate"].replace("%", "").replace("+", ""))
    new_rate = int(base_rate + (speed_mult - 1.0) * 100)
    rate_str = f"+{new_rate}%" if new_rate >= 0 else f"{new_rate}%"

    os.makedirs(PREVIEWS_DIR, exist_ok=True)
    if custom_name:
        clean_name = "".join(c for c in custom_name if c.isalnum() or c in ("-", "_")).strip()
        filename = f"{clean_name or 'audio'}.wav"
    else:
        clean_id = prof["id"].replace("-", "_")
        filename = f"preview_{clean_id}_{os.getpid()}_{abs(hash(text)) % 10000}.wav"

    preview_path = os.path.join(PREVIEWS_DIR, filename)
    temp_mp3 = os.path.join(PREVIEWS_DIR, f".tts_{os.getpid()}_{time.time_ns()}.mp3")

    try:
        logger.info(f"Generando preview con {prof['name']}...")
        comm = edge_tts.Communicate(text, prof["voice"], pitch=prof["pitch"], rate=rate_str)
        await comm.save(temp_mp3)

        source = temp_mp3
        temp_files = [temp_mp3]
        if prof.get("rvc"):
            # edge-tts -> wav -> RVC (voz clonada) -> filtro final
            base_wav = temp_mp3.replace(".mp3", "_base.wav")
            rvc_wav = temp_mp3.replace(".mp3", "_rvc.wav")
            temp_files += [base_wav, rvc_wav]
            p = await asyncio.create_subprocess_exec(
                "ffmpeg", "-y", "-i", temp_mp3, "-ar", "44100", "-ac", "1", base_wav,
                stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL)
            await p.wait()
            logger.info(f"Convirtiendo con RVC ({prof['name']})...")
            await asyncio.get_running_loop().run_in_executor(
                None, rvc_convert, prof["rvc"], base_wav, rvc_wav)
            source = rvc_wav

        cmd = ["ffmpeg", "-y", "-i", source]
        if prof.get("filter"):
            cmd.extend(["-af", prof["filter"]])
        cmd.extend(["-ar", "44100", "-ac", "1", preview_path])

        proc = await asyncio.create_subprocess_exec(
            *cmd, stdout=asyncio.subprocess.DEVNULL, stderr=asyncio.subprocess.DEVNULL
        )
        await proc.wait()

        for tf in temp_files:
            if os.path.exists(tf):
                os.remove(tf)

        logger.info(f"Preview lista en RAM: {preview_path}")
        return web.json_response({
            "success": True,
            "filename": filename,
            "url": f"/audio/{filename}",
            "download_url": f"/audio/{filename}?download=1",
            "voice": prof["name"]
        })

    except Exception as e:
        logger.error(f"Error en síntesis: {e}", exc_info=True)
        return web.json_response({"success": False, "error": "No se pudo generar el audio. Revisa los logs del contenedor."}, status=500)

def main():
    app = web.Application()
    app.router.add_get("/", handle_index)
    app.router.add_get("/health", handle_health)
    app.router.add_get("/api/voices", handle_voices)
    app.router.add_get("/audio/{filename}", handle_audio)
    app.router.add_post("/api/synthesize", handle_synthesize)

    os.makedirs(PREVIEWS_DIR, exist_ok=True)

    logger.info(f"🎭 Voces RVC encontradas: {len(RVC_VOICES)} ({', '.join(v['id'] for v in RVC_VOICES) or 'ninguna'})")
    logger.info(f"🚀 Iniciando Generador de Voz Español en el puerto {PORT}")
    web.run_app(app, host="0.0.0.0", port=PORT)

if __name__ == "__main__":
    main()
