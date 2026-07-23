#!/bin/bash
# ============================================================================
# Install Chatterbox TTS Server (devnen) v2.0.0
# ============================================================================
# Downloads the v2.0.0 release tarball, extracts it, then builds and starts
# the container using the docker-compose file matching the detected GPU
# runtime (ROCm / CUDA / CPU).
#
# Usage:
#   ./install-chatterbox.sh                          # auto-detect GPU
#   INSTALL_DIR=/path ./install-chatterbox.sh        # choose install dir
#   COMPOSE_FILE=docker-compose-cu130.yml ./install-chatterbox.sh  # force file
# ============================================================================
set -euo pipefail

VERSION="v2.0.0"
TARBALL_URL="https://github.com/devnen/Chatterbox-TTS-Server/archive/refs/tags/${VERSION}.tar.gz"
INSTALL_DIR="${INSTALL_DIR:-$(pwd)}"
# GitHub source archives extract to <repo>-<version-without-leading-v>
EXTRACTED_DIR="Chatterbox-TTS-Server-${VERSION#v}"

echo "==> Installing Chatterbox TTS Server ${VERSION} into ${INSTALL_DIR}"
mkdir -p "${INSTALL_DIR}"
cd "${INSTALL_DIR}"

TARBALL="chatterbox-${VERSION}.tar.gz"
echo "==> Downloading ${TARBALL_URL}"
if command -v curl &>/dev/null; then
    curl -fL "${TARBALL_URL}" -o "${TARBALL}"
elif command -v wget &>/dev/null; then
    wget -O "${TARBALL}" "${TARBALL_URL}"
else
    echo "[ERROR] Neither curl nor wget is installed." >&2
    exit 1
fi

echo "==> Extracting ${TARBALL}"
tar -xzf "${TARBALL}"
rm -f "${TARBALL}"

if [ ! -d "${EXTRACTED_DIR}" ]; then
    echo "[ERROR] Expected directory '${EXTRACTED_DIR}' not found after extraction." >&2
    exit 1
fi

cd "${EXTRACTED_DIR}"

# ----------------------------------------------------------------------------
# Detect GPU runtime and pick the matching docker-compose file
# ----------------------------------------------------------------------------
detect_compose() {
    # ROCm / AMD: /dev/kfd device or rocm-smi present
    if [ -e /dev/kfd ] || command -v rocminfo &>/dev/null; then
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

# Store the Hugging Face model cache on the host instead of a named volume
HF_CACHE_DIR="${HF_CACHE_DIR:-/home/user/aimodels/tts}"
mkdir -p "${HF_CACHE_DIR}"
sed -i -E "s|(^[[:space:]]*-[[:space:]]*)hf_cache:/app/hf_cache|\1${HF_CACHE_DIR}:/app/hf_cache|" "${COMPOSE_FILE}"
echo "==> HF cache mapped to ${HF_CACHE_DIR}"

# Pick docker compose (v2 plugin) or docker-compose (v1)
if docker compose version &>/dev/null; then
    DC="docker compose"
elif command -v docker-compose &>/dev/null; then
    DC="docker-compose"
else
    echo "[ERROR] Docker Compose is not installed." >&2
    exit 1
fi

# Force the ROCm GFX override this laptop needs (RX 7000 / gfx1103 iGPU kernels)
if [ "${COMPOSE_FILE}" = "docker-compose-rocm.yml" ]; then
    export HSA_OVERRIDE_GFX_VERSION=11.0.0
    # Rewrite any hardcoded HSA_OVERRIDE_GFX_VERSION line to the forced value
    sed -i -E "s|(^[[:space:]]*-[[:space:]]*HSA_OVERRIDE_GFX_VERSION=).*|\1${HSA_OVERRIDE_GFX_VERSION}|" "${COMPOSE_FILE}"
    echo "==> Forcing HSA_OVERRIDE_GFX_VERSION=${HSA_OVERRIDE_GFX_VERSION}"
fi

echo "==> Detected compose file: ${COMPOSE_FILE}"
echo "==> Building image: ${DC} -f ${COMPOSE_FILE} build"
exec ${DC} -f "${COMPOSE_FILE}" build "$@"
