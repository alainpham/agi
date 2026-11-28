#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
STRATA_DIR="${SCRIPT_DIR}/Strata"
PYTHON="${STRATA_DIR}/terminal/.venv/bin/python"
if [ ! -x "${PYTHON}" ] || [ ! -x "${STRATA_DIR}/build-inkling-cuda/src/inkling2/strata-inkling" ] ||
    [ ! -r /home/user/aimodels/llms/Inkling-2-Mini-SQ-15.strata ]; then
    echo "[ERROR] Run ${SCRIPT_DIR}/install-strata-inkling.sh sq-15 first." >&2
    exit 1
fi

cd "${SCRIPT_DIR}"
exec "${PYTHON}" "${STRATA_DIR}/terminal/serve/server.py" \
    --engine strata --config "${SCRIPT_DIR}/strata-inkling-sq-15-cuda.json" --host 0.0.0.0 --port 9931
