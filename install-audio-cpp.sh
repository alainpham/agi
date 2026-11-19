#!/usr/bin/env bash
# Interactive installer for audio.cpp. Clones and builds under ~/agi.
# AUDIO_BACKEND=cuda|vulkan|hip overrides automatic GPU detection.
set -euo pipefail

AGI_DIR="$HOME/agi"
AUDIO_REPO="${AUDIO_REPO:-https://github.com/0xShug0/audio.cpp.git}"
AUDIO_DIR="$AGI_DIR/audio.cpp"

# ---- colors -----------------------------------------------------------------
if [[ -t 1 ]]; then
  BOLD=$'\e[1m'; DIM=$'\e[2m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'
  BLUE=$'\e[34m'; RED=$'\e[31m'; RESET=$'\e[0m'
else
  BOLD=""; DIM=""; GREEN=""; YELLOW=""; BLUE=""; RED=""; RESET=""
fi

info() { echo "${BLUE}==>${RESET} $*"; }
ok()   { echo "${GREEN}✔${RESET} $*"; }
warn() { echo "${YELLOW}!${RESET} $*"; }
err()  { echo "${RED}✖${RESET} $*" >&2; }

# ---- GPU detection ----------------------------------------------------------
detect_gpu_backend() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "cuda"
    return
  fi

  # Hardware remains visible in sysfs even when this session cannot use NVML.
  local device vendor device_class
  for device in /sys/bus/pci/devices/*; do
    [[ -r "$device/vendor" && -r "$device/class" ]] || continue
    read -r vendor < "$device/vendor"
    read -r device_class < "$device/class"
    if [[ "$vendor" == "0x10de" && "$device_class" == 0x03* ]]; then
      echo "cuda"
      return
    fi
  done
  # Vulkan supports AMD GPUs without requiring ROCm.
  echo "vulkan"
}

# ---- audio.cpp --------------------------------------------------------------
audio_is_installed() {
  [[ -x "$AUDIO_BUILD_DIR/bin/audiocpp_cli" && -x "$AUDIO_BUILD_DIR/bin/audiocpp_server" ]]
}

install_audio() {
  local backend="$1" tool
  info "Installing audio.cpp (backend: ${BOLD}${backend}${RESET})"

  for tool in git cmake; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      err "Required tool missing: $tool"
      return 1
    fi
  done

  if [[ -d "$AUDIO_DIR/.git" ]]; then
    info "Repo already exists, pulling latest…"
    git -C "$AUDIO_DIR" pull --ff-only || warn "git pull failed, building existing checkout"
    git -C "$AUDIO_DIR" submodule update --init --recursive
  else
    git clone --recursive "$AUDIO_REPO" "$AUDIO_DIR"
  fi

  # The upstream helper handles ROCm compiler/architecture detection and the
  # mutually exclusive ENGINE_ENABLE_* flags. Separate caches allow switching
  # between CUDA, Vulkan and HIP without reusing another backend's compiler.
  local -a build_args=(
    --backend "$backend"
    --build-dir "$AUDIO_BUILD_DIR"
    --build-type Release
    --deployment-build
    --jobs "${JOBS:-$(nproc)}"
    --target audiocpp_cli
    --target audiocpp_server
  )
  if [[ "$backend" == "cuda" ]]; then
    build_args+=(--cuda-arch "${CUDA_ARCH:-native}")
  elif [[ "$backend" == "hip" && -n "${GPU_TARGETS:-}" ]]; then
    build_args+=(--gpu-targets "$GPU_TARGETS")
  fi

  (cd "$AUDIO_DIR" && bash scripts/build_linux.sh "${build_args[@]}")

  if ! audio_is_installed; then
    err "Build completed without the expected CLI and server in $AUDIO_BUILD_DIR/bin"
    return 1
  fi
  ok "audio.cpp built → $AUDIO_BUILD_DIR/bin"
  info "Check GPU availability: $AUDIO_BUILD_DIR/bin/audiocpp_cli --list-devices"
}

# ---- status -----------------------------------------------------------------
print_status() {
  local backend="$1"
  echo
  echo "${BOLD}Local AI install status${RESET}"
  echo "${DIM}Install dir: $AGI_DIR${RESET}"
  echo "${DIM}Selected GPU backend: $backend${RESET}"
  echo "${DIM}--------------------------------------------${RESET}"

  if audio_is_installed; then
    ok "audio.cpp        installed ($AUDIO_BUILD_DIR/bin)"
  else
    warn "audio.cpp        not installed for $backend"
  fi
  echo
}

# ---- prompt -----------------------------------------------------------------
confirm() {
  local prompt="$1" reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---- main -------------------------------------------------------------------
main() {
  local backend="${AUDIO_BACKEND:-$(detect_gpu_backend)}"
  case "$backend" in
    cuda|vulkan|hip) ;;
    *) err "Unknown AUDIO_BACKEND: $backend (use cuda, vulkan or hip)"; return 1 ;;
  esac
  AUDIO_BUILD_DIR="$AUDIO_DIR/build/linux-${backend}-release"
  mkdir -p "$AGI_DIR"

  info "Selected GPU backend: $backend"
  print_status "$backend"

  if audio_is_installed; then
    if confirm "audio.cpp is already installed. Rebuild/update it?"; then
      install_audio "$backend"
    else
      info "Skipping audio.cpp."
    fi
  else
    if confirm "Install audio.cpp?"; then
      install_audio "$backend"
    else
      info "Skipping audio.cpp."
    fi
  fi

  echo
  ok "Done."
}

main "$@"
