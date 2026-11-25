#!/usr/bin/env python3
"""True-streaming test for Pocket TTS (en/fr/de) via audiocpp_server.
Streams raw PCM (24 kHz mono s16le) and plays it live through pw-cat (PipeWire).

  ./tts-pocket.sh &                             # start the server (port 8881)
  ./test-tts-stream.py                          # --lang en (default), default sentence
  ./test-tts-stream.py --lang fr
  ./test-tts-stream.py --lang de "Guten Abend."
  ./test-tts-stream.py --all --no-play          # benchmark en, fr and de, no audio
  ./test-tts-stream.py --lang fr --all-voices   # play every French embedding in turn
  ./test-tts-stream.py --lang de --all-voices --no-play --pause 0   # just check each loads
  ./test-tts-stream.py --all --all-voices --save-samples --no-play  # every voice, all languages -> samples/en-alba.wav ...
"""
import argparse, json, os, shutil, subprocess, sys, time, urllib.error, urllib.request, wave

RATE, CH, W = 24000, 1, 2
MODELS = {  # id -> (port, language, sample text)
    "pocket-en": (8881, "en", "Good evening. The harbor is quiet tonight, and the lamps along the pier are just coming on."),
    "pocket-fr": (8881, "fr", "Bonsoir. Le port est calme ce soir, et les lampes le long de la jetée commencent à s'allumer."),
    "pocket-de": (8881, "de", "Guten Abend. Der Hafen ist heute Nacht ruhig, und die Lampen am Pier gehen langsam an."),
}
VOICES = {"pocket-en": "alba", "pocket-fr": "estelle", "pocket-de": "juergen"}  # built-in embeddings
EMB_DIR = "/home/user/aimodels/tts/PocketTTS-GGUF/{}/embeddings"
LANG_DIR = {"en": "english", "fr": "french", "de": "german"}
p = argparse.ArgumentParser()
p.add_argument("text", nargs="?")
p.add_argument("--lang", default="en", choices=["en", "fr", "de"], help="language / model: en, fr or de")
p.add_argument("--voice", help="voice id (embeddings/<id>.safetensors); default per language: alba/estelle/juergen")
p.add_argument("--all-voices", action="store_true", help="test every embedding of --lang, one after another")
p.add_argument("--save-samples", action="store_true", help="with --all-voices: save each voice to <samples-dir>/<lang>-<voice>.wav")
p.add_argument("--samples-dir", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "samples"))
p.add_argument("--pause", type=float, default=0.7, help="seconds of silence between voices with --all-voices")
p.add_argument("--host", default="http://127.0.0.1")
p.add_argument("--all", action="store_true", help="run the sample text for en, fr and de")
p.add_argument("--save", metavar="WAV")
p.add_argument("--no-play", action="store_true")
a = p.parse_args()

def run(model, text, lang, play, save, voice=None):
    port, dlang, dtext = MODELS[model]
    body = {"model": model, "input": text or dtext, "response_format": "pcm", "stream_format": "audio"}
    voice = voice or a.voice or VOICES.get(model)  # Pocket needs a built-in voice id (embeddings/<id>.safetensors) per request
    if voice:
        body["voice"] = voice
    req = urllib.request.Request(f"{a.host}:{port}/v1/audio/speech", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    player = wav = None
    if play:
        if not shutil.which("pw-cat"):
            sys.exit("pw-cat not found; use --no-play")
        player = subprocess.Popen(["pw-cat", "--playback", "--raw", "--format", "s16", "--rate", str(RATE),
                                   "--channels", str(CH), "-"], stdin=subprocess.PIPE)
    if save:
        wav = wave.open(save, "wb"); wav.setnchannels(CH); wav.setsampwidth(W); wav.setframerate(RATE)
    t0 = time.perf_counter(); first = None; total = n = 0; late = 0
    try:
        with urllib.request.urlopen(req) as r:
            while data := r.read1(8192):
                now = time.perf_counter() - t0
                if first is None:
                    first = now
                n += 1; total += len(data)
                # underrun check: audio received so far vs time elapsed since first chunk
                if total / (RATE * CH * W) < (now - first) - 0.05 and n > 1:
                    late += 1
                if player:
                    try: player.stdin.write(data); player.stdin.flush()
                    except BrokenPipeError: print("player exited early", file=sys.stderr); break
                if wav: wav.writeframes(data)
    except urllib.error.HTTPError as e:
        print(f"{model}: HTTP {e.code}: {e.read().decode(errors='replace')}"); return
    except urllib.error.URLError as e:
        print(f"{model}: cannot reach {a.host}:{port}: {e.reason} (start ./tts-pocket.sh)"); return
    finally:
        if wav: wav.close()
        if player:
            try: player.stdin.close()
            except Exception: pass
            player.wait()
    wall = time.perf_counter() - t0; dur = total / (RATE * CH * W)
    if not dur:
        print(f"{model} / {voice}: no audio received (voice file missing?)"); return
    print(f"{model:10s} {voice:15s} first audio {first*1000:6.0f} ms | {n:3d} chunks | audio {dur:5.2f}s | wall {wall:5.2f}s | "
          f"RTF {wall/dur:4.2f} | possible underruns {late}")

if a.all_voices:
    if a.save_samples:
        os.makedirs(a.samples_dir, exist_ok=True)
    for lang in (LANG_DIR if a.all else [a.lang]):  # --all with --all-voices = every language
        d = EMB_DIR.format(LANG_DIR[lang])
        voices = sorted(f[:-len(".safetensors")] for f in os.listdir(d) if f.endswith(".safetensors")) if os.path.isdir(d) else []
        if not voices:
            print(f"no embeddings found in {d}", file=sys.stderr); continue
        print(f"testing {len(voices)} {lang} voices from {d}")
        for i, v in enumerate(voices, 1):
            print(f"[{i}/{len(voices)}]", end=" ", flush=True)
            out = os.path.join(a.samples_dir, f"{lang}-{v}.wav") if a.save_samples else None
            run("pocket-" + lang, a.text, lang, not a.no_play, out, voice=v)
            if not a.no_play and a.pause > 0:
                time.sleep(a.pause)
    if a.save_samples:
        print(f"samples saved in {a.samples_dir}")
elif a.all:
    for m in MODELS:
        run(m, None, None, not a.no_play, None)
else:
    run("pocket-" + a.lang, a.text, a.lang, not a.no_play, a.save)
