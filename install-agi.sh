#!/usr/bin/env bash
# Interactive installer for local AI tooling.
# Clones and builds everything under ~/agi.
set -euo pipefail

AGI_DIR="$HOME/agi"
# https://github.com/TheTom/llama-cpp-turboquant.git
# https://github.com/ggml-org/llama.cpp.git
LLAMA_REPO="${LLAMA_REPO:-https://github.com/ggml-org/llama.cpp.git}"

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
# Returns the cmake backend flag to use for the build.
detect_gpu_backend() {
  if command -v nvidia-smi >/dev/null 2>&1 && nvidia-smi >/dev/null 2>&1; then
    echo "cuda"
  else
    echo "vulkan"
  fi
}

# ---- llama.cpp --------------------------------------------------------------
LLAMA_DIR="$AGI_DIR/llama.cpp"

llama_is_installed() {
  [[ -x "$LLAMA_DIR/build/bin/llama-server" || -x "$LLAMA_DIR/build/bin/llama-cli" ]]
}

install_llama() {
  local backend="$1"
  info "Installing llama.cpp (backend: ${BOLD}${backend}${RESET})"

  if [[ -d "$LLAMA_DIR/.git" ]]; then
    info "Repo already exists, pulling latest…"
    git -C "$LLAMA_DIR" pull --ff-only || warn "git pull failed, building existing checkout"
  else
    git clone "$LLAMA_REPO" "$LLAMA_DIR"
  fi

  local cmake_flag
  case "$backend" in
    cuda)   cmake_flag="-DGGML_CUDA=ON" ;;
    vulkan) cmake_flag="-DGGML_VULKAN=ON" ;;
    *)      err "Unknown backend: $backend"; return 1 ;;
  esac

  cmake -S "$LLAMA_DIR" -B "$LLAMA_DIR/build" "$cmake_flag"
  cmake --build "$LLAMA_DIR/build" --config Release -j "$(nproc)"

  ok "llama.cpp built → $LLAMA_DIR/build/bin"
}

# ---- status -----------------------------------------------------------------
print_status() {
  local backend="$1"
  echo
  echo "${BOLD}Local AI install status${RESET}"
  echo "${DIM}Install dir: $AGI_DIR${RESET}"
  echo "${DIM}Detected GPU backend: $backend${RESET}"
  echo "${DIM}--------------------------------------------${RESET}"

  if llama_is_installed; then
    ok "llama.cpp        installed ($LLAMA_DIR/build/bin)"
  else
    warn "llama.cpp        not installed"
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

  # llama.cpp
  if llama_is_installed; then
    if confirm "llama.cpp is already installed. Rebuild/update it?"; then
      install_llama "$backend"
    else
      info "Skipping llama.cpp."
    fi
  else
    if confirm "Install llama.cpp?"; then
      install_llama "$backend"
    else
      info "Skipping llama.cpp."
    fi
  fi

  echo
  ok "Done."
}

main "$@"
