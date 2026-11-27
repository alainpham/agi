#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_SERVER="${AUDIO_SERVER:-$SCRIPT_DIR/audio.cpp/build/linux-${AUDIO_BACKEND:-vulkan}-release/bin/audiocpp_server}"
MODEL=/home/user/aimodels/tts/tiny-voca-orig.gguf

if [[ ! -x "$AUDIO_SERVER" ]]; then
    echo "[ERROR] audiocpp_server is missing or not executable: $AUDIO_SERVER" >&2
    echo "Run ./install-audio-cpp.sh or set AUDIO_SERVER to your server binary." >&2
    exit 1
fi
if [[ ! -r "$MODEL" ]]; then
    echo "[ERROR] Model is missing or unreadable: $MODEL" >&2
    exit 1
fi

# Tiny Voca is designed for CPU inference, regardless of the build's GPU backend.
# Override defaults with TTS_HOST, PORT, THREADS, or extra server arguments.
exec "$AUDIO_SERVER" \
    --config "$SCRIPT_DIR/tts-tinyvoca.json" \
    --backend cpu \
    --host "${TTS_HOST:-0.0.0.0}" \
    --port "${PORT:-8880}" \
    --threads "${THREADS:-4}" \
    --ui \
    "$@"
