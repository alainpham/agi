#!/usr/bin/env bash
# One audiocpp_server for TTS (Pocket TTS en/fr/de) + STT (Nemotron 3.5 ASR streaming 0.6B).
#   TTS: POST /v1/audio/speech               model pocket-en | pocket-fr | pocket-de (send "voice", e.g. alba)
#   STT: POST /v1/audio/transcriptions/live  model nemotron (native cache-aware streaming, ~320 ms chunks;
#        live PCM in, SSE text out). One request at a time per model id.
# Models load on first use (lazy_load). Override with PORT, THREADS, TTS_HOST.
set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUDIO_SERVER="$SCRIPT_DIR/audio.cpp/build/linux-cpu-release/bin/audiocpp_server"
CONFIG="$SCRIPT_DIR/audiocpp.json"

if [[ ! -x "$AUDIO_SERVER" ]]; then
    echo "[ERROR] CPU audiocpp_server missing: $AUDIO_SERVER (run ./install-audio-cpp.sh)" >&2; exit 1
fi
for f in /home/user/aimodels/tts/PocketTTS-GGUF/{english,french,german}/pocket-tts-*-q8_0.gguf \
         /home/user/aimodels/stt/nemotron-3.5-asr-streaming-0.6b-q8_0.gguf; do
    [[ -r "$f" ]] || { echo "[ERROR] model missing: $f" >&2; exit 1; }
done

exec "$AUDIO_SERVER" \
    --config "$CONFIG" \
    --backend cpu \
    --host "${TTS_HOST:-0.0.0.0}" \
    --port "${PORT:-8881}" \
    --threads "${THREADS:-6}" \
    "$@"
