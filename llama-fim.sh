#!/usr/bin/env bash
# Fill-in-the-middle / code completion server (e.g. llama.vim, llama.vscode).
#
# Runs llama-server in router mode with the presets in llama-fim.ini.
# Clients choose a model per request with "model": "<preset name>", e.g.
#   curl localhost:9931/v1/models
#   curl localhost:9931/infill -d '{"model":"qwen2.5-coder-1.5b","input_prefix":"def add(a, b):\n    ","input_suffix":"\n"}'
# Requests without a "model" field are rejected by the router.
# Extra arguments are passed to llama-server and override the presets.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
LLAMA_SERVER="${SCRIPT_DIR}/llama.cpp/build/bin/llama-server"
PRESETS="${FIM_PRESETS:-${SCRIPT_DIR}/llama-fim.ini}"

if [[ ! -x "${LLAMA_SERVER}" ]]; then
    echo "[ERROR] llama-server is missing or not executable: ${LLAMA_SERVER}" >&2
    exit 1
fi
if [[ ! -r "${PRESETS}" ]]; then
    echo "[ERROR] Presets file is missing or unreadable: ${PRESETS}" >&2
    exit 1
fi

# Check the devices this llama-server can actually use, including CUDA build support.
if devices="$("${LLAMA_SERVER}" --list-devices 2>/dev/null)" && \
    [[ "${devices}" =~ (^|[[:space:]])CUDA[0-9]+: ]]; then
    echo "==> CUDA device detected; using CUDA settings"
    # --n-cpu-moe only affects MoE models (Cyber-Tiel); dense models have no expert tensors.
    backend_options=(--no-mmproj-offload --threads 14 --n-cpu-moe 40)
else
    echo "==> No CUDA device detected; using Vulkan settings"
    backend_options=(--threads 6)
fi

# --models-max 2: FIM + one chat model; loading another unloads the least recently used.
exec "${LLAMA_SERVER}" \
    --models-preset "${PRESETS}" \
    --models-max 1 \
    --host 0.0.0.0 \
    --port 9931 \
    "${backend_options[@]}" \
    "$@"
