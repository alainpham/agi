#!/usr/bin/env bash
# Clone or update Xolotl and build its CUDA engines with the upstream ggml patch.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/Xolotl"
BUILD_DIR="${INSTALL_DIR}/build-xolotl"
VENV="${INSTALL_DIR}/.venv"

for tool in git python3; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        echo "[ERROR] ${tool} is required to install Xolotl." >&2
        exit 1
    fi
done

cuda_arch="${CUDA_ARCH:-}"
if [[ -z "${cuda_arch}" ]]; then
    if ! capabilities="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null)" ||
        ! read -r capability <<< "${capabilities}" ||
        [[ ! "${capability}" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Could not detect NVIDIA compute capability. Set CUDA_ARCH for the target GPU." >&2
        exit 1
    fi
    cuda_arch="${capability//./}"
fi

if [[ -e "${INSTALL_DIR}/.git" ]]; then
    echo "==> Updating Xolotl at ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" pull --ff-only
else
    echo "==> Cloning Xolotl into ${INSTALL_DIR}"
    git clone https://github.com/Indras-Mirror/Xolotl.git "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"
if [[ ! -x "${VENV}/bin/python" ]]; then
    python3 -m venv "${VENV}"
fi

echo "==> Installing Xolotl Python and build dependencies"
"${VENV}/bin/python" -m pip install -r requirements.txt -r requirements-build.txt

echo "==> Preparing Xolotl's pinned llama.cpp dependency"
bash tools/xolotl/fetch-llama.sh

echo "==> Building Xolotl for CUDA architecture ${cuda_arch}"
PATH="${VENV}/bin:${PATH}" "${VENV}/bin/cmake" -S . -B "${BUILD_DIR}" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_CUDA_ARCHITECTURES="${cuda_arch}" \
    -DSTRATA_ENABLE_CUDA=ON \
    -DSTRATA_GGML_CUDA=ON \
    -DSTRATA_MMQ_KQUANTS=ON \
    -DSTRATA_GGML_DIR="${INSTALL_DIR}/third_party/llama.cpp" \
    -DSTRATA_DSV41_FQ_OP=ON \
    -DSTRATA_DSV41_HC_MIX=ON \
    -DSTRATA_BUILD_TESTS=OFF
"${VENV}/bin/cmake" --build "${BUILD_DIR}" --parallel "${JOBS:-4}"

echo "==> Xolotl build complete. Binaries are in ${BUILD_DIR}"
