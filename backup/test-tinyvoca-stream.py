#!/usr/bin/env python3
"""Pseudo-streaming with Tiny Voca (offline model): split text into sentences,
fetch each one from audiocpp_server while the previous one is playing, and feed
everything to one pw-cat process (PipeWire) so playback is gapless.

Usage:
  ./test-tinyvoca-stream.py                       # default text
  ./test-tinyvoca-stream.py "Some long text. Another sentence."
  echo "text from a pipe" | ./test-tinyvoca-stream.py -
  ./test-tinyvoca-stream.py --voice F2 --speed 1.1 --save out.wav --no-play
Start the server first: ./tts-tinyvoca.sh   (stdlib only; needs pw-cat to play)
"""
import argparse, io, json, queue, re, shutil, subprocess, sys, threading, time
import urllib.error, urllib.request, wave

p = argparse.ArgumentParser()
p.add_argument("text", nargs="?", default="Hello! This is Tiny Voca. It is a very small model, "
               "so each sentence is generated quickly. While one sentence plays, the next one is "
               "already being prepared. That is how we get streaming from an offline model.")
p.add_argument("--url", default="http://127.0.0.1:8880")
p.add_argument("--model", default="tiny-voca")
p.add_argument("--voice", default="F2", help="M2 (male) or F2 (female)")
p.add_argument("--speed", type=float, default=1.0)
p.add_argument("--max-chars", type=int, default=160, help="split sentences longer than this at commas")
p.add_argument("--save", metavar="WAV", help="also write the audio to a WAV file")
p.add_argument("--no-play", action="store_true")
a = p.parse_args()
text = sys.stdin.read() if a.text == "-" else a.text

def split(t):
    out = []
    for s in re.split(r"(?<=[.!?;:])\s+|\n+", t.strip()):
        s = s.strip()
        while len(s) > a.max_chars:  # break long sentences at the last comma/space in range
            cut = max(s.rfind(",", 0, a.max_chars), s.rfind(" ", 0, a.max_chars))
            cut = cut if cut > 20 else a.max_chars
            out.append(s[:cut + 1].strip()); s = s[cut + 1:].strip()
        if s:
            out.append(s)
    return out

def synth(sentence):
    body = {"model": a.model, "input": sentence, "voice": a.voice,
            "options": {"voice_id": a.voice, "speed": a.speed}}
    req = urllib.request.Request(a.url + "/v1/audio/speech", json.dumps(body).encode(),
                                 {"Content-Type": "application/json"})
    with urllib.request.urlopen(req) as r, wave.open(io.BytesIO(r.read())) as w:
        return w.readframes(w.getnframes()), w.getframerate(), w.getnchannels()

sentences = split(text)
if not sentences:
    sys.exit("no text")

q = queue.Queue(maxsize=2)   # fetch at most 2 sentences ahead
def producer():
    try:
        for s in sentences:
            t = time.perf_counter()
            pcm, rate, ch = synth(s)
            q.put((s, pcm, rate, ch, time.perf_counter() - t))
    except urllib.error.HTTPError as e:
        q.put(RuntimeError(f"HTTP {e.code}: {e.read().decode(errors='replace')}"))
    except urllib.error.URLError as e:
        q.put(RuntimeError(f"cannot reach server at {a.url}: {e.reason} (run ./tts-tinyvoca.sh)"))
    q.put(None)

t0 = time.perf_counter()
threading.Thread(target=producer, daemon=True).start()

player = wav = None
total = n = 0
rate = None
try:
    while (item := q.get()) is not None:
        if isinstance(item, Exception):
            sys.exit(str(item))
        s, pcm, rate, ch, gen = item
        if player is None and not a.no_play:
            if not shutil.which("pw-cat"):
                sys.exit("pw-cat not found; use --no-play")
            player = subprocess.Popen(["pw-cat", "--playback", "--raw", "--format", "s16",
                                       "--rate", str(rate), "--channels", str(ch), "-"],
                                      stdin=subprocess.PIPE)
        if a.save and wav is None:
            wav = wave.open(a.save, "wb"); wav.setnchannels(ch); wav.setsampwidth(2); wav.setframerate(rate)
        n += 1
        dur = len(pcm) / (rate * ch * 2)
        total += dur
        if n == 1:
            print(f"time to first audio: {(time.perf_counter()-t0)*1000:.0f} ms")
        print(f"  [{n}/{len(sentences)}] gen {gen*1000:5.0f} ms  audio {dur:5.2f}s  RTF {gen/dur:.2f}  | {s[:60]}")
        if player:
            try: player.stdin.write(pcm); player.stdin.flush()
            except BrokenPipeError: sys.exit("player exited early")
        if wav: wav.writeframes(pcm)
finally:
    if wav: wav.close()
    if player:
        try: player.stdin.close()
        except Exception: pass
        player.wait()

wall = time.perf_counter() - t0
print(f"\n{n} sentences, {total:.2f}s of audio, {wall:.2f}s wall"
      + (" (no playback)" if a.no_play else ""))
