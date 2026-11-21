#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/Xolotl"
PYTHON="${INSTALL_DIR}/.venv/bin/python"
CONFIG="${SCRIPT_DIR}/xolotl-inkling-xq.json"
MODEL_DIR=/home/user/aimodels/llms
MODEL="${MODEL_DIR}/Inkling-2-Mini-XQ-Uncensored.gguf"
DRAFT="${MODEL_DIR}/Inkling-2-Mini-XQ-Uncensored-DSpark-BF16.gguf"
PACK="${INSTALL_DIR}/build-xolotl/inkling-xq"

if [ ! -x "${PYTHON}" ] || [ ! -x "${INSTALL_DIR}/build-xolotl/xolotl-inkling" ]; then
    echo "[ERROR] Xolotl installation is incomplete. Run ${SCRIPT_DIR}/install-xolotl.sh first." >&2
    exit 1
fi

for gguf in "${MODEL}" "${DRAFT}"; do
    if [ ! -r "${gguf}" ] || [ "$(head -c 4 -- "${gguf}")" != GGUF ]; then
        echo "[ERROR] Expected a readable GGUF at ${gguf}" >&2
        exit 1
    fi
done

cd "${INSTALL_DIR}"
tokenizer_ready=true
for file in vocab.json merges.txt token_type.json tokenizer.json chat_template.jinja; do
    if [ ! -s "${PACK}/tokenizer/${file}" ] || [ "${MODEL}" -nt "${PACK}/tokenizer/${file}" ]; then
        tokenizer_ready=false
        break
    fi
done
if [ "${tokenizer_ready}" = false ]; then
    echo "==> Extracting the Inkling tokenizer from ${MODEL}"
    "${PYTHON}" tools/strata_tokenizer.py --gguf "${MODEL}" --out "${PACK}"
fi

echo "==> Using Xolotl config: ${CONFIG}"
exec "${PYTHON}" -m serve.server --engine strata --config "${CONFIG}" --port "${XOLOTL_PORT:-9931}"
