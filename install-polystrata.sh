#!/usr/bin/env bash
# Update/build PolyStrata and extract each model's tokenizer; use the configs beside this script.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
INSTALL_DIR="${SCRIPT_DIR}/PolyStrata"
MODEL="${1:-}"
case "${MODEL}" in
    ''|inkling|inkling-q8) ;;
    *) echo "Usage: $0 [inkling|inkling-q8]" >&2; exit 1 ;;
esac

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

SETUP_DIR="${INSTALL_DIR}"
if [[ -f "${INSTALL_DIR}/terminal/setup.py" ]]; then
    SETUP_DIR="${INSTALL_DIR}/terminal"
fi
VENV_DIR="${SETUP_DIR}/.venv"
if [[ ! -x "${VENV_DIR}/bin/python" && -x "${INSTALL_DIR}/.venv/bin/python" ]]; then
    VENV_DIR="${INSTALL_DIR}/.venv"
fi
if [[ ! -x "${VENV_DIR}/bin/python" ]]; then
    python3 -m venv "${VENV_DIR}"
fi

cd "${SETUP_DIR}"

# Reuse setup's build routines without its model downloads or config generation.
"${VENV_DIR}/bin/python" - "${SCRIPT_DIR}" "${INSTALL_DIR}" "${MODEL}" <<'PY'
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
install_dir = Path(sys.argv[2])
configs = []
requested_model = sys.argv[3]
if requested_model in ("inkling", "inkling-q8") and hip:
    raise SystemExit("[ERROR] This Inkling launcher requires CUDA.")
model_names = (requested_model,) if requested_model else ("tiel", "cybertiel")
for name in model_names:
    stem = "inkling-ud-q8_k_xl" if name == "inkling-q8" else f"{name}-ud-q4_k_xl"
    path = Path(sys.argv[1]) / f"strata-{stem}-{backend}.json"
    cfg = json.loads(path.read_text())
    model = install_dir / cfg["args"][cfg["args"].index("--model") + 1]
    for required in (model, install_dir / cfg["vision"]["mmproj"]):
        if not required.is_file():
            raise SystemExit(f"[ERROR] Required local GGUF is missing: {required}")
    configs.append((path, cfg, model))

# Keep the two engines and their build stamps separate as well as the configs.
# Reuse an existing installation from before the backend split when it matches.
legacy_name = setup.ENGINE_POLY_DIR
target = install_dir / f"engine-poly-{backend}"
setup.ENGINE_POLY_DIR = str(target)
if not target.exists():
    for directory in dict.fromkeys((install_dir, setup.ROOT)):
        legacy = directory / legacy_name
        legacy_stamp = legacy / "BUILD.json"
        if legacy_stamp.is_file():
            legacy_meta = json.loads(legacy_stamp.read_text())
            if (legacy_meta.get("backend") == "hip") == hip:
                shutil.copytree(legacy, target)
                break

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
    tokenizer = install_dir / cfg["tokenizer"]
    required = ("vocab.json", "merges.txt", "token_type.json", "tokenizer.json", "chat_template.jinja")
    if not all((tokenizer / name).is_file() for name in required):
        env = os.environ.copy()
        if llama is not None and (llama / "gguf-py" / "gguf").is_dir():
            env.setdefault("STRATA_GGUF_PY", str(llama / "gguf-py"))
        setup.run(
            [sys.executable, str(setup.ROOT / "tools" / "strata_tokenizer.py"),
             "--gguf", str(model), "--out", str(tokenizer.parent)],
            env=env,
        )
    # Each model learns and saves its own expert usage; no initial profile download is needed.
    profile = install_dir / cfg["args"][cfg["args"].index("--expert-profile") + 1]
    profile.parent.mkdir(parents=True, exist_ok=True)
    cfg.update(exe=str(engine / setup.POLY_EXE), cwd=str(install_dir),
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

if [[ "${MODEL}" == inkling-q8 ]]; then
    echo "==> Build complete. Start ./strata-inkling-ud-q8_k_xl.sh beside this installer."
elif [[ "${MODEL}" == inkling ]]; then
    echo "==> Build complete. Start ./strata-inkling-ud-q4_k_xl.sh beside this installer."
else
    echo "==> Build complete. Start ./strata-tiel-ud-q4_k_xl.sh or ./strata-cybertiel-ud-q4_k_xl.sh beside this installer."
fi
