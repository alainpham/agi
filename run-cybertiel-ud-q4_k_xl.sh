#!/bin/sh
set -eu
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"
cd "${INSTALL_DIR}"
exec "${INSTALL_DIR}/.venv/bin/python" "${INSTALL_DIR}/serve/server.py" \
    --engine strata --config "${SCRIPT_DIR}/strata-cybertiel-ud-q4_k_xl.json" --port 9931
