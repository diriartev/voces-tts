# ==============================================================
# Voces TTS - edge-tts + clonación de voz RVC (CPU)
# Contenedor endurecido, sin root, filesystem de solo lectura
# ==============================================================
FROM python:3.15-slim

LABEL org.opencontainers.image.title="Voces TTS"
LABEL org.opencontainers.image.description="Generador de voz en español con edge-tts y voces clonadas RVC"

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    PORT=5055 \
    MODELS_DIR=/app/modelos_rvc \
    HOME=/home/appuser \
    NUMBA_CACHE_DIR=/tmp/numba \
    MPLCONFIGDIR=/tmp/mpl

# DL3008: no se fijan versiones de apt para recibir los parches de seguridad de Debian
# hadolint ignore=DL3008
RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg ca-certificates curl build-essential \
    && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# 1. PyTorch solo CPU (mucho más ligero que la versión CUDA) + dependencias fijadas.
#    pip<24.1 y setuptools 69 son necesarios para instalar fairseq; después se
#    actualiza setuptools y se quitan pip/wheel de la imagen final.
COPY requirements-torch.txt requirements.txt /tmp/
RUN pip install --no-cache-dir "pip==24.0" "setuptools==69.5.1" "wheel==0.43.0" && \
    pip install --no-cache-dir -r /tmp/requirements-torch.txt \
        --extra-index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir -r /tmp/requirements.txt \
        --extra-index-url https://download.pytorch.org/whl/cpu && \
    pip install --no-cache-dir "setuptools==80.9.0" && \
    pip uninstall -y wheel pip && \
    rm -rf /tmp/*.txt /root/.cache

# 2. Modelos base de RVC (HuBERT + RMVPE) de Hugging Face, verificados por SHA-256
#    (si alguien los cambiara en origen, la construcción falla)
ARG RVC_BASE=https://huggingface.co/lj1995/VoiceConversionWebUI/resolve/main
SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN LIB=$(python3 -c "import rvc_python,os;print(os.path.dirname(rvc_python.__file__))"); \
    B="$LIB/base_model" && mkdir -p "$B" && \
    for f in hubert_base.pt rmvpe.pt rmvpe.onnx; do \
        curl -fL --retry 3 -o "$B/$f" "$RVC_BASE/$f"; \
    done && \
    printf '%s\n' \
      "f54b40fd2802423a5643779c4861af1e9ee9c1564dc9d32f54f20b5ffba7db96  $B/hubert_base.pt" \
      "6d62215f4306e3ca278246188607209f09af3dc77ed4232efdd069798c4ec193  $B/rmvpe.pt" \
      "5370e71ac80af8b4b7c793d27efd51fd8bf962de3a7ede0766dac0befa3660fd  $B/rmvpe.onnx" \
    | sha256sum -c -

# 3. Parches: rvc-python sin escrituras en disco (read-only) y carga SEGURA de
#    modelos .pth (weights_only=True: un .pth malicioso no puede ejecutar código)
COPY patch_rvc.py /tmp/patch_rvc.py
RUN python3 /tmp/patch_rvc.py && rm /tmp/patch_rvc.py

# 4. Usuario sin privilegios
RUN groupadd -g 1000 appgroup && \
    useradd -u 1000 -g appgroup -d /home/appuser -m -s /sbin/nologin appuser

WORKDIR /app
RUN mkdir -p /app/modelos_rvc
COPY --chown=appuser:appgroup server.py /app/server.py
COPY --chown=appuser:appgroup public /app/public
RUN chmod 555 /app /app/public && chmod 444 /app/server.py /app/public/*

USER 1000:1000
EXPOSE 5055

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD ["curl", "-fsS", "--max-time", "4", "http://127.0.0.1:5055/health"]

CMD ["python3", "server.py"]
