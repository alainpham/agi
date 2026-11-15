#!/usr/bin/env bash
# Update/build PolyStrata and extract each model's tokenizer; use the configs beside this script.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"

if ! command -v git >/dev/null 2>&1; then
    echo "[ERROR] Git is required to install PolyStrata." >&2
    exit 1
fi

if [[ -d "${INSTALL_DIR}/.git" ]]; then
    echo "==> Updating PolyStrata at ${INSTALL_DIR}"
    git -C "${INSTALL_DIR}" pull --ff-only
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
import shutil
import sys

# This installer also targets the laptop's Radeon 740M (Phoenix/Hawk Point).
# setup reads this opt-in at import time; an explicit value of 0 still disables it.
os.environ.setdefault("STRATA_EXPERIMENTAL_GFX1103", "1")
import setup

gpu = setup.gpu_info(0)
hip = gpu is None
if hip:
    amd = setup.amd_gpus()
    usable = [card for card in amd if setup.amd_problem(card) is None]
    if usable:
        gpu = min(usable, key=setup.amd_rank)
    else:
        details = "; ".join(f"{card['name']}: {setup.amd_problem(card)}" for card in amd)
        raise SystemExit("[ERROR] No supported AMD GPU detected. " +
                         (details or "The amdgpu driver must expose the GPU through KFD topology."))
print(f"==> Building for {gpu['name']} ({gpu['arch']}, {'HIP' if hip else 'CUDA'})")
if hip and gpu["arch"] == "gfx1103":
    print("==> Experimental Radeon 740M/760M/780M support; ROCm is reused or installed locally by setup.")

backend = "amd" if hip else "cuda"
configs = []
for name in ("tiel", "cybertiel"):
    path = Path(sys.argv[1]) / f"strata-{name}-ud-q4_k_xl-{backend}.json"
    cfg = json.loads(path.read_text())
    model = Path(cfg["args"][cfg["args"].index("--model") + 1])
    for required in (model, Path(cfg["vision"]["mmproj"])):
        if not required.is_file():
            raise SystemExit(f"[ERROR] Required local GGUF is missing: {required}")
    configs.append((path, cfg, model))

# Keep the two engines and their build stamps separate as well as the configs.
# Reuse an existing installation from before the backend split when it matches.
legacy = setup.ROOT / setup.ENGINE_POLY_DIR
setup.ENGINE_POLY_DIR = f"engine-poly-{backend}"
target = setup.ROOT / setup.ENGINE_POLY_DIR
legacy_stamp = legacy / "BUILD.json"
if not target.exists() and legacy_stamp.is_file():
    legacy_meta = json.loads(legacy_stamp.read_text())
    if (legacy_meta.get("backend") == "hip") == hip:
        shutil.copytree(legacy, target)

setup.pip_install(
    setup.requirement_lines() if setup.REQUIREMENTS.exists() else setup.PY_PACKAGES,
    "PolyStrata Python and build dependencies",
)
llama = setup.get_llama_cpp()
if hip:
    engine = setup.build_engine_poly_hip(gpu, llama)
    stamp = engine / "BUILD.json"
    meta = json.loads(stamp.read_text())
    # strata-poly's HIP builder only builds text inference. Build the existing
    # CPU image encoder separately to keep the supplied vision configs usable.
    setup.build_vision_cpu(engine, stamp, meta, setup.get_llama_cpp(vision=True),
                           setup.source_hash(setup.VISION_SOURCES))
else:
    toolkit, _ = setup.cuda_choice([gpu["arch"]], poly=True)
    engine = setup.build_engine_poly(gpu, True, llama, vision="cpu", toolkit=toolkit)
meta = json.loads((engine / "BUILD.json").read_text())

for path, cfg, model in configs:
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
    cfg.update(exe=str(engine / setup.POLY_EXE), cwd=str(setup.ROOT),
               backend="hip" if hip else "cuda", lib_dirs=meta.get("lib_dirs") or meta.get("cuda_dirs", []),
               gpu=gpu["index"], gpus_asked=True)
    cfg.pop("hip_ordinal", None)
    if hip:
        cfg.pop("cuda", None)
        # ROCm cannot return released KV allocations to its free pool reliably.
        if "--kv-whole" not in cfg["args"]:
            cfg["args"].append("--kv-whole")
    else:
        cfg["cuda"] = toolkit
    cfg["vision"].update(exe=str(engine / setup.VEXE), gpu=False)
    temporary = path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(cfg, indent=1) + "\n")
    temporary.replace(path)
    print(f"==> {cfg['model_name']}: tokenizer {tokenizer}, expert profile {profile}")
PY

echo "==> Build complete. Start ./strata-tiel-ud-q4_k_xl.sh or ./strata-cybertiel-ud-q4_k_xl.sh beside this installer."
