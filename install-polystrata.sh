#!/usr/bin/env bash
# Build PolyStrata and extract each model's tokenizer; use the configs beside this script.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git is required to install PolyStrata." >&2
    exit 1
fi

if [[ -d "${INSTALL_DIR}/.git" ]]; then
    echo "==> Using existing PolyStrata checkout at ${INSTALL_DIR}"
else
    echo "==> Cloning PolyStrata into ${INSTALL_DIR}"
    git clone https://github.com/simplexai-labs/PolyStrata "${INSTALL_DIR}"
fi

cd "${INSTALL_DIR}"
if [[ ! -x .venv/bin/python ]]; then
    python3 -m venv .venv
fi

# Reuse setup's build routines without its model downloads or config generation.
.venv/bin/python - "${SCRIPT_DIR}" <<'PY'
import json
import os
from pathlib import Path
import sys

import setup

configs = []
for name in ("tiel", "cybertiel"):
    path = Path(sys.argv[1]) / f"strata-{name}-ud-q4_k_xl.json"
    cfg = json.loads(path.read_text())
    model = Path(cfg["args"][cfg["args"].index("--model") + 1])
    for required in (model, Path(cfg["vision"]["mmproj"])):
        if not required.is_file():
            raise SystemExit(f"[ERROR] Required local GGUF is missing: {required}")
    configs.append((cfg, model))

gpu = setup.gpu_info(0)
if gpu is None:
    raise SystemExit("[ERROR] NVIDIA GPU 0 is required to build this installation.")

setup.pip_install(
    setup.requirement_lines() if setup.REQUIREMENTS.exists() else setup.PY_PACKAGES,
    "PolyStrata Python and build dependencies",
)
toolkit, _ = setup.cuda_choice([gpu["arch"]], poly=True)
llama = setup.get_llama_cpp()
setup.build_engine_poly(gpu, True, llama, vision="cpu", toolkit=toolkit)

for cfg, model in configs:
    tokenizer = Path(cfg["tokenizer"])
    required = ("vocab.json", "merges.txt", "token_type.json", "tokenizer.json", "chat_template.jinja")
    if not all((tokenizer / name).is_file() for name in required):
        setup.run(
            [sys.executable, str(setup.ROOT / "tools" / "strata_tokenizer.py"),
             "--gguf", str(model), "--out", str(tokenizer.parent)],
            env=dict(os.environ, STRATA_GGUF_PY=str(llama / "gguf-py")),
        )
    # Each model learns and saves its own expert usage; no initial profile download is needed.
    profile = Path(cfg["args"][cfg["args"].index("--expert-profile") + 1])
    profile.parent.mkdir(parents=True, exist_ok=True)
    print(f"==> {cfg['model_name']}: tokenizer {tokenizer}, expert profile {profile}")
PY

echo "==> Build complete. Start ./run-tiel-ud-q4_k_xl.sh or ./run-cybertiel-ud-q4_k_xl.sh beside this installer."
