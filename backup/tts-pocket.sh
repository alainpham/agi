#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_SERVER="${AUDIO_SERVER:-$SCRIPT_DIR/audio.cpp/build/linux-${AUDIO_BACKEND:-vulkan}-release/bin/audiocpp_server}"

if [[ ! -x "$AUDIO_SERVER" ]]; then
    echo "[ERROR] audiocpp_server missing: $AUDIO_SERVER (run ./install-audio-cpp.sh)" >&2; exit 1
fi

# Small model, CPU is the sensible default here. Override with BACKEND, PORT, THREADS, TTS_HOST.
exec "$AUDIO_SERVER" \
    --config "$SCRIPT_DIR/tts-pocket.json" \
    --backend "${BACKEND:-cpu}" \
    --host "${TTS_HOST:-0.0.0.0}" \
    --port "${PORT:-8881}" \
    --threads "${THREADS:-6}" \
    "$@"
