#!/bin/bash
# ============================================================================
# Start Chatterbox TTS Server
# ============================================================================
# Detects the GPU runtime (ROCm / CUDA / CPU) and starts the container using
# the matching docker-compose file. Assumes the image is already built
# (see install-chatterbox.sh).
#
# Usage:
#   ./chatterbox.sh [start|stop|restart|down|logs|status]   (default: start)
#     start    build/detect config + start containers (docker compose up -d)
#     stop     stop containers (keep them)              (docker compose stop)
#     restart  restart containers                       (docker compose restart)
#     down     stop and remove containers + network     (docker compose down)
#     logs     follow container logs                    (docker compose logs -f)
#     status   show container status                    (docker compose ps)
#
#   CHATTERBOX_DIR=/path/to/Chatterbox-TTS-Server-2.0.0 ./chatterbox.sh
#   COMPOSE_FILE=docker-compose-cu130.yml ./chatterbox.sh   # force file
# ============================================================================
set -euo pipefail

CMD="${1:-start}"
[ $# -gt 0 ] && shift

# ----------------------------------------------------------------------------
# Locate the Chatterbox directory (holds the docker-compose files)
# ----------------------------------------------------------------------------
DIR="${CHATTERBOX_DIR:-$(pwd)}"
if [ ! -f "${DIR}/docker-compose.yml" ]; then
    # Fall back to a Chatterbox-TTS-Server-* subdirectory
    match=$(find "${DIR}" -maxdepth 1 -type d -name 'Chatterbox-TTS-Server-*' | head -n1)
    if [ -n "${match}" ]; then
        DIR="${match}"
    fi
fi
cd "${DIR}"

# ----------------------------------------------------------------------------
# Detect GPU runtime and pick the matching docker-compose file
# ----------------------------------------------------------------------------
detect_compose() {
    # ROCm / AMD: /dev/kfd device or rocm-smi present
    if [ -e /dev/kfd ] || command -v rocm-smi &>/dev/null || command -v rocminfo &>/dev/null; then
        echo "docker-compose-rocm.yml"
        return
    fi
    # CUDA / NVIDIA: nvidia-smi present or /dev/nvidia* device
    if command -v nvidia-smi &>/dev/null || ls /dev/nvidia* &>/dev/null; then
        echo "docker-compose.yml"
        return
    fi
    # Fallback: CPU-only
    echo "docker-compose-cpu.yml"
}

COMPOSE_FILE="${COMPOSE_FILE:-$(detect_compose)}"

if [ ! -f "${COMPOSE_FILE}" ]; then
    echo "[ERROR] Compose file '${COMPOSE_FILE}' not found in $(pwd)." >&2
    exit 1
fi

# Pick docker compose (v2 plugin) or docker-compose (v1)
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    echo "[ERROR] Docker Compose is not installed." >&2
    exit 1
fi

echo "==> Compose file: ${COMPOSE_FILE}"

case "${CMD}" in
    start|up)
        # Store the Hugging Face model cache on the host instead of a named volume
        HF_CACHE_DIR="${HF_CACHE_DIR:-/home/user/aimodels/tts}"
        mkdir -p "${HF_CACHE_DIR}"
        sed -i -E "s|(^[[:space:]]*-[[:space:]]*)hf_cache:/app/hf_cache|\1${HF_CACHE_DIR}:/app/hf_cache|" "${COMPOSE_FILE}"
        echo "==> HF cache mapped to ${HF_CACHE_DIR}"

        # Force the ROCm GFX override this laptop needs (Radeon 780M / gfx1103
        # iGPU is unsupported; route to gfx1100/RDNA3 kernels)
        if [ "${COMPOSE_FILE}" = "docker-compose-rocm.yml" ]; then
            export HSA_OVERRIDE_GFX_VERSION=11.0.0
            if grep -qE "^[[:space:]]*-[[:space:]]*HSA_OVERRIDE_GFX_VERSION=" "${COMPOSE_FILE}"; then
                # Line already present (uncommented): overwrite its value
                sed -i -E "s|(^[[:space:]]*-[[:space:]]*HSA_OVERRIDE_GFX_VERSION=).*|\1${HSA_OVERRIDE_GFX_VERSION}|" "${COMPOSE_FILE}"
            else
                # Not present: insert it as the first item under 'environment:'
                sed -i -E "s|^([[:space:]]*)environment:[[:space:]]*\$|\1environment:\n\1  - HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}|" "${COMPOSE_FILE}"
            fi
            echo "==> Forcing HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"

            # The image has no 'render'/'video' groups by name; use host GIDs
            RENDER_GID=$(getent group render | cut -d: -f3)
            VIDEO_GID=$(getent group video | cut -d: -f3)
            [ -n "${RENDER_GID}" ] && sed -i -E "s|(^[[:space:]]*-[[:space:]]*)render[[:space:]]*$|\1\"${RENDER_GID}\"|" "${COMPOSE_FILE}"
            [ -n "${VIDEO_GID}" ]  && sed -i -E "s|(^[[:space:]]*-[[:space:]]*)video[[:space:]]*$|\1\"${VIDEO_GID}\"|" "${COMPOSE_FILE}"
            echo "==> group_add GIDs: render=${RENDER_GID:-n/a} video=${VIDEO_GID:-n/a}"
        fi

        echo "==> Starting: ${DC} -f ${COMPOSE_FILE} up -d"
        exec ${DC} -f "${COMPOSE_FILE}" up -d "$@"
        ;;
    stop)
        echo "==> Stopping: ${DC} -f ${COMPOSE_FILE} stop"
        exec ${DC} -f "${COMPOSE_FILE}" stop "$@"
        ;;
    restart)
        echo "==> Restarting: ${DC} -f ${COMPOSE_FILE} restart"
        exec ${DC} -f "${COMPOSE_FILE}" restart "$@"
        ;;
    down)
        echo "==> Bringing down: ${DC} -f ${COMPOSE_FILE} down"
        exec ${DC} -f "${COMPOSE_FILE}" down "$@"
        ;;
    logs)
        exec ${DC} -f "${COMPOSE_FILE}" logs -f "$@"
        ;;
    status|ps)
        exec ${DC} -f "${COMPOSE_FILE}" ps "$@"
        ;;
    *)
        echo "[ERROR] Unknown command '${CMD}'. Use: start|stop|restart|down|logs|status" >&2
        exit 1
        ;;
esac
