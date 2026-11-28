#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_SERVER="${SCRIPT_DIR}/llama.cpp/build/bin/llama-server"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "[ERROR] llama-server is missing or not executable: ${LLAMA_SERVER}" >&2
    exit 1
fi

# Check the devices this llama-server can actually use, including CUDA build support.
if devices="$("${LLAMA_SERVER}" --list-devices 2>/dev/null)" && \
    [[ "${devices}" =~ (^|[[:space:]])CUDA[0-9]+: ]]; then
    echo "==> CUDA device detected; using CUDA settings"
    backend_options=(--no-mmproj-offload --threads 14 --n-cpu-moe 40)
else
    echo "==> No CUDA device detected; using Vulkan settings"
    backend_options=(--threads 6)
fi

exec "${LLAMA_SERVER}" \
    --model /home/user/aimodels/llms/Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf \
    --alias Cyber-Tiel-Coder-35B-A3B-MTP \
    --mmproj /home/user/aimodels/llms/mmproj-BF16.gguf \
    --host 0.0.0.0 \
    --port 9931 \
    --reasoning on \
    --load-mode mlock \
    --ctx-size 81920 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --spec-type draft-mtp --spec-draft-n-max 2 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 \
    --n-gpu-layers 999 \
    "${backend_options[@]}"
