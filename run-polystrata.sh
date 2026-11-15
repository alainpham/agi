#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"

case "${1:-}" in
    tiel|cybertiel) model="$1" ;;
    *) echo "Usage: $0 tiel|cybertiel" >&2; exit 1 ;;
esac

# A responding NVIDIA driver with at least one GPU takes priority on mixed PCs.
backend=""
if command -v nvidia-smi >/dev/null 2>&1 && \
    devices="$(nvidia-smi --query-gpu=index --format=csv,noheader 2>/dev/null)" && \
    [ -n "${devices}" ]; then
    backend="cuda"
else
    for vendor in /sys/class/drm/card*/device/vendor; do
        if [ -r "${vendor}" ] && [ "$(cat "${vendor}")" = "0x1002" ]; then
            backend="amd"
            break
        fi
    done
fi
if [ -z "${backend}" ]; then
    echo "[ERROR] No working NVIDIA GPU or AMD Radeon detected." >&2
    exit 1
fi

config="${SCRIPT_DIR}/strata-${model}-ud-q4_k_xl-${backend}.json"
if [ ! -x "${INSTALL_DIR}/engine-poly-${backend}/strata-poly" ] || \
    [ ! -x "${INSTALL_DIR}/.venv/bin/python" ] || [ ! -f "${config}" ]; then
    echo "[ERROR] ${backend} installation is incomplete. Run ${SCRIPT_DIR}/install-polystrata.sh first." >&2
    exit 1
fi
echo "==> Using ${backend} config: ${config}"
cd "${INSTALL_DIR}"
exec "${INSTALL_DIR}/.venv/bin/python" "${INSTALL_DIR}/serve/server.py" \
    --engine strata --config "${config}" --port 9931
