#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"

quant=ud-q4_k_xl
case "${1:-}" in
    tiel|cybertiel|inkling) model="$1" ;;
    inkling-q8) model=inkling; quant=ud-q8_k_xl ;;
    *) echo "Usage: $0 tiel|cybertiel|inkling|inkling-q8" >&2; exit 1 ;;
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

config="${SCRIPT_DIR}/strata-${model}-${quant}-${backend}.json"
if [ "${model}" = inkling ] && [ "${backend}" != cuda ]; then
    echo "[ERROR] This Inkling launcher requires CUDA." >&2
    exit 1
fi
SERVER_DIR="${INSTALL_DIR}"
if [ -f "${INSTALL_DIR}/terminal/serve/server.py" ]; then
    SERVER_DIR="${INSTALL_DIR}/terminal"
fi
python="${SERVER_DIR}/.venv/bin/python"
if [ ! -x "${python}" ]; then
    python="${INSTALL_DIR}/.venv/bin/python"
fi
if [ ! -x "${INSTALL_DIR}/engine-poly-${backend}/strata-poly" ] || \
    [ ! -x "${python}" ] || [ ! -f "${SERVER_DIR}/serve/server.py" ] || [ ! -f "${config}" ]; then
    installer="${SCRIPT_DIR}/install-polystrata.sh"
    if [ "${model}" = inkling ]; then
        installer="${installer} $1"
    fi
    echo "[ERROR] ${backend} installation is incomplete. Run ${installer} first." >&2
    exit 1
fi
echo "==> Using ${backend} config: ${config}"
cd "${INSTALL_DIR}"
set -- --engine strata --config "${config}" --port 9931
if [ "${model}" = inkling ] && [ -n "${STRATA_API_KEY:-}" ]; then
    set -- "$@" --host 0.0.0.0
fi
exec "${python}" "${SERVER_DIR}/serve/server.py" "$@"
