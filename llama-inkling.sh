#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
RELEASE="b12588-mix-c0c3de8"
BUNDLE="cuda13-portable"
RUNTIME_DIR="${SCRIPT_DIR}/llama.cpp-unsloth-${RELEASE}-${BUNDLE}"
LLAMA_SERVER="${RUNTIME_DIR}/llama-server"
MODEL_DIR="/home/user/aimodels/llms"

install_runtime() (
    local staging_dir archive url checksum
    staging_dir="$(mktemp -d -- "${RUNTIME_DIR}.XXXXXXXX")"
    trap 'rm -rf -- "${staging_dir}"' EXIT
    archive="${staging_dir}/bundle.tar.gz"
    url="https://github.com/unslothai/llama.cpp/releases/download/${RELEASE}/app-${RELEASE}-linux-x64-${BUNDLE}.tar.gz"
    checksum="6c1985d2d75c9cc6b299891d557aca70843ba5ccb68f14863a50687048cfdd48"

    echo "==> Installing Unsloth llama.cpp ${RELEASE} (${BUNDLE})"
    curl --fail --location --retry 2 --output "${archive}" "${url}"
    printf '%s  %s\n' "${checksum}" "${archive}" | sha256sum --check
    mkdir -- "${staging_dir}/runtime"
    tar -xzf "${archive}" -C "${staging_dir}/runtime"
    mv --no-clobber --no-target-directory -- "${staging_dir}/runtime" "${RUNTIME_DIR}" || \
        [[ -d "${RUNTIME_DIR}" ]]
)

if [[ ! -e "${RUNTIME_DIR}" ]]; then
    install_runtime
fi

if [[ ! -x "${LLAMA_SERVER}" || ! -f "${RUNTIME_DIR}/libggml-cuda.so" ]] || \
    ! grep -Fxq -- "variant: ${BUNDLE}" "${RUNTIME_DIR}/BUILD_INFO.txt" || \
    ! version="$("${LLAMA_SERVER}" --version 2>&1)" || \
    [[ "${version}" != *"(build 12588, commit 883286076)"* ]]; then
    echo "[ERROR] Expected Unsloth llama.cpp ${RELEASE} (${BUNDLE}) in ${RUNTIME_DIR}" >&2
    exit 1
fi

if ! devices="$("${LLAMA_SERVER}" --list-devices 2>&1)" || \
    [[ ! "${devices}" =~ (^|[[:space:]])CUDA[0-9]+: ]]; then
    echo "[ERROR] The Unsloth CUDA build could not find a CUDA device." >&2
    printf '%s\n' "${devices}" >&2
    exit 1
fi

exec "${LLAMA_SERVER}" \
    --model "${MODEL_DIR}/Inkling-2-Mini-UD-Q4_K_XL.gguf" \
    --alias Inkling-2-Mini \
    --mmproj "${MODEL_DIR}/inkling-2-mini-mmproj-BF16.gguf" \
    --host 0.0.0.0 \
    --port 9931 \
    --reasoning on \
    --load-mode mlock --lazy-mode off \
    --fit on --fit-target 512 \
    --ctx-size 102400 --batch-size 512 --ubatch-size 256 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --cache-ram 0 \
    --no-mmproj-offload \
    --threads 14 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --spec-type draft-dspark \
    --spec-draft-model "${MODEL_DIR}/dspark-Inkling-2-Mini-Q8_0.gguf" \
    --spec-draft-n-max 2 --n-gpu-layers-draft 99 \
    --temp 1.0 --top-p 1.0 --top-k 0 --min-p 0.0
