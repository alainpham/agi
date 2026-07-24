#!/bin/bash
# ============================================================================
# Start Kokoro FastAPI TTS Server
# ============================================================================
# Detects the GPU runtime (ROCm / CUDA / CPU) and runs the matching prebuilt
# remsky/kokoro-fastapi image. Serves the OpenAI-compatible TTS API on :8880.
#
# Usage:
#   ./kokoro.sh [start|stop|restart|rm|logs|status]   (default: start)
#     start    run the container (docker run -d)
#     stop     stop the container                     (docker stop)
#     restart  restart the container                  (docker restart)
#     rm       stop and remove the container          (docker rm -f)
#     logs     follow container logs                  (docker logs -f)
#     status   show container status                  (docker ps)
#
#   KOKORO_IMAGE=ghcr.io/remsky/kokoro-fastapi-gpu:latest ./kokoro.sh  # force
#   KOKORO_PORT=9000 ./kokoro.sh                                       # port
# ============================================================================
set -euo pipefail

CMD="${1:-start}"
[ $# -gt 0 ] && shift

NAME="${KOKORO_NAME:-kokoro}"
PORT="${KOKORO_PORT:-8880}"

# ----------------------------------------------------------------------------
# Detect GPU runtime and pick the matching image
# ----------------------------------------------------------------------------
detect_image() {
    # ROCm / AMD: /dev/kfd device or rocm-smi present
    if [ -e /dev/kfd ] || command -v rocminfo &>/dev/null; then
        echo "ghcr.io/remsky/kokoro-fastapi-rocm:latest"
        return
    fi
    # CUDA / NVIDIA: nvidia-smi present or /dev/nvidia* device
    if command -v nvidia-smi &>/dev/null || ls /dev/nvidia* &>/dev/null; then
        echo "ghcr.io/remsky/kokoro-fastapi-gpu:latest"
        return
    fi
    # Fallback: CPU-only
    echo "ghcr.io/remsky/kokoro-fastapi-cpu:latest"
}

IMAGE="${KOKORO_IMAGE:-$(detect_image)}"

case "${CMD}" in
    start|up|run)
        echo "==> Image: ${IMAGE}"

        # Build the runtime-specific device/gpu flags
        GPU_ARGS=()
        case "${IMAGE}" in
            *-rocm:*)
                GPU_ARGS=(--device=/dev/kfd --device=/dev/dri
                          --group-add video --group-add render
                          --security-opt seccomp=unconfined
                          -e HSA_OVERRIDE_GFX_VERSION=11.0.0)
                echo "==> ROCm: forcing HSA_OVERRIDE_GFX_VERSION=11.0.0"
                ;;
            *-gpu:*)
                GPU_ARGS=(--gpus all)
                echo "==> CUDA: --gpus all"
                ;;
            *)
                echo "==> CPU-only image"
                ;;
        esac

        echo "==> Starting: docker run -d --name ${NAME} -p ${PORT}:8880 ${IMAGE}"
        exec docker run -d --name "${NAME}" \
            "${GPU_ARGS[@]}" \
            -p "${PORT}:8880" \
            "${IMAGE}" "$@"
        ;;
    stop)
        exec docker stop "${NAME}"
        ;;
    restart)
        exec docker restart "${NAME}"
        ;;
    rm|down)
        exec docker rm -f "${NAME}"
        ;;
    logs)
        exec docker logs -f "${NAME}" "$@"
        ;;
    status|ps)
        exec docker ps -a --filter "name=^/${NAME}$"
        ;;
    *)
        echo "[ERROR] Unknown command '${CMD}'. Use: start|stop|restart|rm|logs|status" >&2
        exit 1
        ;;
esac
