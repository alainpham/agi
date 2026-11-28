#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
STRATA_DIR="${SCRIPT_DIR}/Strata"
TERMINAL_DIR="${STRATA_DIR}/terminal"
VENV_DIR="${TERMINAL_DIR}/.venv"
VENV_BIN="${VENV_DIR}/bin"

MODEL_DIR="/home/user/aimodels/llms"
PACK_DIR="/home/user/aimodels/Strata-data/packs/inkling-sqv2-20"
HF="https://huggingface.co/strata-engine/Inkling-2-Mini-Strata/resolve"
REVISION="c234774038d1c9249cb33637d27b895d47b39786"
PATCH="${SCRIPT_DIR}/patches/strata-inkling-sqv2.patch"

case "${1:-sqv2-20}" in
    sqv2-20)
        variant="sqv2-20"
        model="Inkling-2-Mini-SQv2-20.strata"
        model_revision="16b2170"
        model_checksum="429671f8eb5b50e593856e6eb82ebb7da9d1f07e99b553438b196f72cc86a6d6"
        ;;
    sq-15)
        variant="sq-15"
        model="Inkling-2-Mini-SQ-15.strata"
        model_revision="2d2d96e"
        model_checksum="2ea32eed533afba257e2cbee7b073dc2c3da80fe55d1d2d794779b5498e30737"
        ;;
    sq-10)
        variant="sq-10"
        model="Inkling-2-Mini-SQ-10.strata"
        model_revision="2d2d96e"
        model_checksum="ac4d452ad03e4930abd9d46f9c5eec22b2f75a1da45a1e49bd24ccd58b065934"
        ;;
    *) echo "Usage: $0 [sqv2-20|sq-15|sq-10]" >&2; exit 1 ;;
esac

download() {
    local url="$1" path="$2" checksum="$3"
    if [[ -f "${path}" ]]; then
        printf '%s  %s\n' "${checksum}" "${path}" | sha256sum --check
        return
    fi
    curl --fail --location --retry 4 --continue-at - --output "${path}.part" "${url}"
    printf '%s  %s\n' "${checksum}" "${path}.part" | sha256sum --check
    mv -- "${path}.part" "${path}"
}

mkdir -p -- "${MODEL_DIR}" "${PACK_DIR}"
download "${HF}/${model_revision}/${model}?download=true" "${MODEL_DIR}/${model}" "${model_checksum}"
download "${HF}/5623ceb/Inkling-2-Mini-Vision-v2.strata?download=true" \
    "${MODEL_DIR}/Inkling-2-Mini-Vision-v2.strata" 34a176505276729b58744fc9ee40a5005bbff9a590d8e1f7dbe82baf33ef07d5
download "${HF}/0dfe4c3/tokenizer.json" \
    "${PACK_DIR}/tokenizer.hf.json" 7f332727f9a3f093dd452a39cc978e6757627e5dad1b0673aa4e75174f236dd6
download "${HF}/75446fe/chat_template.jinja" \
    "${PACK_DIR}/chat_template.jinja" 53a9035f3255945704b5857657cfb00c1165090c0641c4f782a0cbf268cc16dc

if [[ ! -d "${STRATA_DIR}" ]]; then
    staging="$(mktemp -d -- "${SCRIPT_DIR}/.strata-inkling.XXXXXXXX")"
    trap 'rm -rf -- "${staging}"' EXIT
    download "https://codeload.github.com/Niko1221/Strata/tar.gz/${REVISION}" "${staging}/source.tar.gz" \
        98e48030e34b0d558688a3357b20720dc6bdf6c931aee1040844b0f8b78d305e
    mkdir -- "${staging}/source"
    tar -xzf "${staging}/source.tar.gz" --strip-components=1 -C "${staging}/source"
    patch --directory "${staging}/source" --strip=1 --input "${PATCH}"
    mv --no-clobber --no-target-directory -- "${staging}/source" "${STRATA_DIR}"
fi
if ! patch --directory "${STRATA_DIR}" --strip=1 --reverse --dry-run --silent --force --input "${PATCH}"; then
    echo "[ERROR] Expected the SQv2-compatible Strata source in ${STRATA_DIR}." >&2
    exit 1
fi

if [[ ! -x "${VENV_BIN}/python" ]]; then
    python3 -m venv "${VENV_DIR}"
fi
"${VENV_BIN}/python" -m pip install --disable-pip-version-check \
    -r "${TERMINAL_DIR}/requirements.txt" -r "${TERMINAL_DIR}/requirements-build.txt"

"${VENV_BIN}/python" "${TERMINAL_DIR}/tools/inkling_tokenizer.py" \
    --hf-json "${PACK_DIR}/tokenizer.hf.json" --template "${PACK_DIR}/chat_template.jinja" --out "${PACK_DIR}/tokenizer"

build_dir="${STRATA_DIR}/build-inkling-cuda"
"${VENV_BIN}/cmake" -S "${STRATA_DIR}/engine" -B "${build_dir}" -G Ninja \
    -DCMAKE_MAKE_PROGRAM="${VENV_BIN}/ninja" -DCMAKE_BUILD_TYPE=Release \
    -DSTRATA_ENABLE_CUDA=ON -DSTRATA_BUILD_TESTS=OFF \
    -DCMAKE_CUDA_COMPILER=/opt/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=86
"${VENV_BIN}/cmake" --build "${build_dir}" --target strata-inkling -j 6
echo "==> Start ${SCRIPT_DIR}/strata-inkling-${variant}.sh"
