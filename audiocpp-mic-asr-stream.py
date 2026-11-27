#!/usr/bin/env python3
"""Mix several PipeWire sources into one stream and transcribe it live with audiocpp_server.

Default sources (sinks are captured through their .monitor):
  from-desktop.monitor   desktop audio
  from-caller.monitor    what the caller sends you
  mic01-processed        microphone 1
  mic02-processed        microphone 2

Each source is captured with parec as s16le 16 kHz mono, the four are summed sample by
sample (with clipping) every --chunk-ms, and the mix is sent as one live request to
POST /v1/audio/transcriptions/live (model "nemotron"). Text is printed to stdout as it arrives; each line starts with a timestamp, and a new line
starts at a word boundary roughly every --line-seconds (default 3) or after that long a pause:

  [12:03:41] so the deploy went out at nine and
  [12:03:44] the alerts fired a minute later

Usage:
  ./audiocpp.sh &                                   # server (port 8881)
  ./audiocpp-mic-asr-stream.py                      # Ctrl-C to stop
  ./audiocpp-mic-asr-stream.py --language fr-FR     # Nemotron language prompt (en-US, fr-FR, de-DE, auto, ...)
  ./audiocpp-mic-asr-stream.py --sources mic01-processed,from-caller.monitor
  ./audiocpp-mic-asr-stream.py --sources mic01-processed --save-mix mix.wav   # choose the recording file
  ./audiocpp-mic-asr-stream.py --no-save-mix                                  # don't record
The mix is recorded by default to recordings/mix-<date>-<time>.wav (16 kHz mono, exactly what the model hears).
Stdlib only; needs parec (PipeWire's PulseAudio tools) for capture.
"""
import argparse, array, json, os, shutil, signal, socket, subprocess, sys, threading, time, wave
from urllib.parse import urlencode

RATE, CHANNELS, WIDTH = 16000, 1, 2
DEFAULT_SOURCES = "from-desktop.monitor,from-caller.monitor,mic01-processed,mic02-processed"

p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
p.add_argument("--sources", default=DEFAULT_SOURCES, help="comma-separated PipeWire/Pulse source names")
p.add_argument("--model", default="nemotron")
p.add_argument("--host", default="127.0.0.1")
p.add_argument("--port", type=int, default=8881)
p.add_argument("--language", help="language prompt passed to the model, e.g. en-US, fr-FR, de-DE or auto")
p.add_argument("--gain", type=float, default=1.0, help="gain applied to every source before mixing")
p.add_argument("--chunk-ms", type=int, default=100, help="audio mixed and sent per HTTP chunk")
p.add_argument("--partials", action="store_true", help="also print provisional (partial) transcripts (to stderr)")
p.add_argument("--line-seconds", type=float, default=3.0, help="start a new line after about this long (at a word boundary) or after this much silence")
p.add_argument("--prebuffer-ms", type=int, default=300, help="audio buffered per source before mixing starts; absorbs capture jitter")
p.add_argument("--save-mix", metavar="WAV", help="WAV file for the mix sent to the model "
               "(default: recordings/mix-<date>-<time>.wav next to this script)")
p.add_argument("--no-save-mix", action="store_true", help="do not record the mix")
a = p.parse_args()

if not shutil.which("parec"):
    sys.exit("parec not found (install pulseaudio-utils / pipewire-pulse tools)")

SOURCES = [s.strip() for s in a.sources.split(",") if s.strip()]
CHUNK = RATE * CHANNELS * WIDTH * a.chunk_ms // 1000   # bytes per mixed chunk
MAX_BUF = CHUNK * 10                                   # drop audio older than ~1 s if a source runs ahead
stop = threading.Event()
out_lock = threading.Lock()

def log(msg):
    with out_lock:
        print(msg, file=sys.stderr, flush=True)

class LineWriter:
    """Writes transcript deltas inline, with a timestamp at the start of each line. A new line starts only at a word boundary,
    once the current line is --line-seconds old, or after --line-seconds of silence."""

    def __init__(self, every):
        self.every, self.started, self.last, self.open = every, 0.0, 0.0, False
        threading.Thread(target=self.idle_flush, daemon=True).start()

    def write(self, delta):
        if not delta:
            return
        with out_lock:
            now = time.monotonic()
            if not self.open:
                delta = delta.lstrip()
                if not delta:
                    return
                self.started, self.open = now, True
                sys.stdout.write(self.stamp())
            elif now - self.started >= self.every and delta[:1].isspace():
                # the previous word is complete (next delta starts a new word): break the line here
                sys.stdout.write("\n" + self.stamp())
                delta = delta.lstrip()
                self.started = now
            sys.stdout.write(delta)
            sys.stdout.flush()
            self.last = now

    @staticmethod
    def stamp():
        return f"[{time.strftime('%H:%M:%S')}] "

    def end_line(self):
        with out_lock:
            if self.open:
                sys.stdout.write("\n"); sys.stdout.flush()
                self.open = False

    def idle_flush(self):
        while not stop.is_set():
            time.sleep(0.25)
            if self.open and time.monotonic() - self.last >= self.every:
                self.end_line()

out = None  # LineWriter, created in main()

def emit(text, partial=False):
    if partial:  # provisional text goes to stderr so it doesn't break the transcript lines
        if text.strip():
            log(f"~ {text.strip()}")
        return
    out.write(text)

class Capture:
    """Reads one source with parec into a byte buffer the mixer drains."""

    def __init__(self, device):
        self.device, self.buf, self.lock = device, bytearray(), threading.Lock()
        self.proc = subprocess.Popen(["parec", f"--device={device}", "--format=s16le", f"--rate={RATE}",
                                      f"--channels={CHANNELS}", "--raw", f"--latency-msec={a.chunk_ms}"],
                                     stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        threading.Thread(target=self.read, daemon=True).start()

    def read(self):
        while not stop.is_set():
            data = self.proc.stdout.read1(CHUNK) if hasattr(self.proc.stdout, "read1") else self.proc.stdout.read(CHUNK)
            if not data:
                err = self.proc.stderr.read().decode(errors="replace").strip()
                if not stop.is_set():
                    log(f"[capture] {self.device} stopped{': ' + err if err else ''} (mixing silence for it)")
                return
            with self.lock:
                self.buf += data
                if len(self.buf) > MAX_BUF:
                    del self.buf[:len(self.buf) - MAX_BUF]

    def trim(self, n):
        """Keep only the newest n bytes (used at session start so a reconnect doesn't add latency)."""
        with self.lock:
            if len(self.buf) > n:
                del self.buf[:len(self.buf) - n]

    def take(self, n):
        """Return exactly n bytes: what is buffered, padded with silence if this source is behind or idle."""
        with self.lock:
            data = bytes(self.buf[:n]); del self.buf[:n]
        return data + b"\x00" * (n - len(data))

    def close(self):
        self.proc.terminate()
        try: self.proc.wait(timeout=2)
        except subprocess.TimeoutExpired: self.proc.kill()

def mix(chunks):
    total = array.array("i", [0]) * (CHUNK // WIDTH)
    for c in chunks:
        s = array.array("h"); s.frombytes(c)
        for i, v in enumerate(s):
            total[i] += v
    g = a.gain
    out = array.array("h", (max(-32768, min(32767, int(v * g))) for v in total))
    return out.tobytes()

def send_audio(sock, captures, mixwav):
    """Every chunk-ms, mix one chunk from every source and send it as an HTTP chunk."""
    pre = RATE * CHANNELS * WIDTH * a.prebuffer_ms // 1000
    for c in captures:
        c.trim(pre)
    period, nxt = a.chunk_ms / 1000, time.monotonic()
    try:
        while not stop.is_set():
            nxt += period
            delay = nxt - time.monotonic()
            if delay > 0:
                time.sleep(delay)
            else:
                nxt = time.monotonic()  # fell behind; don't try to catch up with a burst
            data = mix([c.take(CHUNK) for c in captures])
            if mixwav:
                mixwav.writeframes(data)
            sock.sendall(f"{len(data):X}\r\n".encode() + data + b"\r\n")
        sock.sendall(b"0\r\n\r\n")  # terminating chunk = end of speech; server then sends the final transcript
    except OSError:
        pass

def sse_lines(f, chunked):
    buf = b""
    while True:
        if chunked:
            size = f.readline()
            if not size:
                return
            n = int(size.split(b";")[0].strip() or b"0", 16)
            if n == 0:
                return
            data = f.read(n); f.readline()
        else:
            data = f.read1(4096)
            if not data:
                return
        buf += data
        while b"\n" in buf:
            line, buf = buf.split(b"\n", 1)
            yield line.decode(errors="replace").rstrip("\r")

def session(captures, mixwav):
    q = {"model": a.model, "sample_rate": RATE, "channels": CHANNELS, "sample_format": "s16le"}
    if a.language:
        q["language"] = a.language
    sock = socket.create_connection((a.host, a.port), timeout=10)
    sock.settimeout(None)
    sock.sendall((f"POST /v1/audio/transcriptions/live?{urlencode(q)} HTTP/1.1\r\n"
                  f"Host: {a.host}:{a.port}\r\nContent-Type: application/octet-stream\r\n"
                  "Transfer-Encoding: chunked\r\nAccept: text/event-stream\r\nConnection: close\r\n\r\n").encode())
    threading.Thread(target=send_audio, args=(sock, captures, mixwav), daemon=True).start()
    try:
        f = sock.makefile("rb")
        status = f.readline().decode(errors="replace").strip()
        headers = {}
        while (line := f.readline()) not in (b"\r\n", b"\n", b""):
            k, _, v = line.decode(errors="replace").partition(":")
            headers[k.strip().lower()] = v.strip()
        if " 200" not in status:
            log(f"server said {status}: {f.read(2000).decode(errors='replace').strip()}")
            time.sleep(2)
            return
        for line in sse_lines(f, "chunked" in headers.get("transfer-encoding", "").lower()):
            if not line.startswith("data:"):
                continue
            payload = line[5:].strip()
            if payload == "[DONE]":
                return
            try:
                ev = json.loads(payload)
            except ValueError:
                continue
            t = ev.get("type", "")
            if t == "transcript.text.delta":
                emit(ev.get("delta") or ev.get("text") or "")
            elif t == "transcript.text.partial" and a.partials:
                emit(ev.get("text", ""), partial=True)
            elif t == "transcript.text.done":
                if stop.is_set():
                    out.end_line()
                    log(f"final: {ev.get('text', '').strip()}")
            elif t == "error" or "error" in ev:
                log(f"error event: {ev.get('error', ev)}")
    finally:
        sock.close()

def main():
    global out
    out = LineWriter(a.line_seconds)
    signal.signal(signal.SIGINT, lambda *_: stop.set())
    signal.signal(signal.SIGTERM, lambda *_: stop.set())
    captures = [Capture(s) for s in SOURCES]
    mixwav = None
    if not a.no_save_mix:
        if not a.save_mix:
            rec_dir = os.path.join(os.path.dirname(os.path.abspath(__file__)), "recordings")
            os.makedirs(rec_dir, exist_ok=True)
            a.save_mix = os.path.join(rec_dir, time.strftime("mix-%Y%m%d-%H%M%S.wav"))
        log(f"recording mix to {a.save_mix}")
        mixwav = wave.open(a.save_mix, "wb")
        mixwav.setnchannels(CHANNELS); mixwav.setsampwidth(WIDTH); mixwav.setframerate(RATE)
    time.sleep(a.prebuffer_ms / 1000)  # let every source fill its jitter buffer before the first mix
    log(f"mixing {', '.join(SOURCES)} -> {a.model} at {a.host}:{a.port}  (Ctrl-C to stop)")
    try:
        while not stop.is_set():
            try:
                session(captures, mixwav)      # returns when the server ends the request (e.g. time limit); reconnect
            except OSError as e:
                if stop.is_set():
                    break
                log(f"connection problem: {e}; retrying in 2 s")
                time.sleep(2)
    finally:
        stop.set()
        out.end_line()
        for c in captures:
            c.close()
        if mixwav:
            mixwav.close()
            log(f"mix saved to {a.save_mix}")

if __name__ == "__main__":
    main()
