#!/usr/bin/env bash
# Interactive installer for local AI tooling.
# Clones and builds everything under ~/agi.
set -euo pipefail

AGI_DIR="$HOME/agi"
SD_REPO="${SD_REPO:-https://github.com/leejet/stable-diffusion.cpp.git}"
SD_DIR="$AGI_DIR/stable-diffusion.cpp"

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
# Returns the CMake backend to use for the build.
detect_gpu_backend() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "cuda"
  else
    echo "vulkan"
  fi
}

# ---- stable-diffusion.cpp ---------------------------------------------------
sd_is_installed() {
  [[ -x "$SD_DIR/build/bin/sd-cli" || -x "$SD_DIR/build/bin/sd-server" ]]
}

install_sd() {
  local backend="$1"
  info "Installing stable-diffusion.cpp (backend: ${BOLD}${backend}${RESET})"

  if [[ -d "$SD_DIR/.git" ]]; then
    info "Repo already exists, pulling latest…"
    git -C "$SD_DIR" pull --ff-only || warn "git pull failed, building existing checkout"
    git -C "$SD_DIR" submodule update --init --recursive
  else
    git clone --recursive "$SD_REPO" "$SD_DIR"
  fi

  local -a cmake_flags
  case "$backend" in
    cuda)
      cmake_flags=(-DSD_CUDA=ON -DSD_HIPBLAS=OFF -DSD_VULKAN=OFF)
      ;;
    vulkan)
      cmake_flags=(-DSD_CUDA=OFF -DSD_HIPBLAS=OFF -DSD_VULKAN=ON)
      ;;
    *)
      err "Unknown backend: $backend"
      return 1
      ;;
  esac

  cmake -S "$SD_DIR" -B "$SD_DIR/build" -DCMAKE_BUILD_TYPE=Release "${cmake_flags[@]}"
  cmake --build "$SD_DIR/build" --config Release -j "$(nproc)"

  ok "stable-diffusion.cpp built → $SD_DIR/build/bin"
}

# ---- status -----------------------------------------------------------------
print_status() {
  local backend="$1"
  echo
  echo "${BOLD}Local AI install status${RESET}"
  echo "${DIM}Install dir: $AGI_DIR${RESET}"
  echo "${DIM}Detected GPU backend: $backend${RESET}"
  echo "${DIM}--------------------------------------------${RESET}"

  if sd_is_installed; then
    ok "stable-diffusion.cpp installed ($SD_DIR/build/bin)"
  else
    warn "stable-diffusion.cpp not installed"
  fi
  echo
}

# ---- prompt -----------------------------------------------------------------
confirm() {
  # confirm "question" -> returns 0 for yes
  local prompt="$1" reply
  read -r -p "$prompt [y/N] " reply
  [[ "$reply" =~ ^[Yy]$ ]]
}

# ---- main -------------------------------------------------------------------
main() {
  mkdir -p "$AGI_DIR"

  local backend
  backend="$(detect_gpu_backend)"
  if [[ "$backend" == "cuda" ]]; then
    info "NVIDIA GPU detected → building with CUDA."
  else
    info "No NVIDIA GPU detected → building with Vulkan."
  fi

  print_status "$backend"

  if sd_is_installed; then
    if confirm "stable-diffusion.cpp is already installed. Rebuild/update it?"; then
      install_sd "$backend"
    else
      info "Skipping stable-diffusion.cpp."
    fi
  else
    if confirm "Install stable-diffusion.cpp?"; then
      install_sd "$backend"
    else
      info "Skipping stable-diffusion.cpp."
    fi
  fi

  echo
  ok "Done."
}

main "$@"
