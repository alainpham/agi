#!/usr/bin/env bash
# Qwen3.8-Flash-Next tuned for: RTX 3060 Laptop 6 GB + i7-12700H + 31 GB RAM
# MEASURED on this box (build 11028, IQ4_XS, all warmed, n_predict 128-400):
#   -ngl 99 ............ CUDA OOM (compute pp buffers don't fit in 6 GB) -- unusable
#   draft-mtp .......... UNSUPPORTED: this IQ4_XS build has no MTP tensors
#                        ("model doesn't contain MTP layers") -- use ngram-mod
#   spec off ........... code tg 5.8 t/s
#   ngram 24/8/16 ...... code tg 8.1 (cold pool) / 14.3 (hot pool), prose tg ~8.5-8.9
#                        --> short drafts ~2.2-2.5x on repetitive/code (pp/tg ~= 1 here,
#                            so long 48/64 drafts can't pay off; docs assume big-GPU ratios)
#   threads 6/6 ........ warm tg 5.4, code-hot 7.9
#   threads 12/16 ...... warm tg 8.9, code-hot 14.3 --> ~1.7x, keep (experts live on CPU)
#   -ngl 30 ............ warm tg 5.2 (3783 MiB VRAM, headroom but slower)
#   -ngl 48 ............ warm tg 8.9, code-hot 14.3 (5777 MiB VRAM, fits) --> keep, max offload
#   pp ~9 t/s (CPU experts dominate prefill); ctx 8192 keeps KV+buffers small.
# NOTE: PLE n-gram table (weights) != --spec-type ngram-* (drafting). Both kept.
# NOTE: -fit off is mandatory (auto-fit mis-sizes this arch). mmap+lazy keeps the
#   39 GB n-gram table pageable from SSD. --cache-ram 0 saves ~8 GB RAM on this box.

/home/$USER/agi/llama.cpp/build/bin/llama-server \
    -hf AtomicChat/Qwen3.8-Flash-Next-GGUF:IQ4_XS \
    --host 0.0.0.0 \
    --port 8080 \
    --jinja \
    -ngl 42 \
    -cmoe \
    --no-mmproj \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --spec-type ngram-mod \
    --spec-ngram-mod-n-match 24 \
    --spec-ngram-mod-n-min 8 \
    --spec-ngram-mod-n-max 16 \
    -c 4000 -fit off

# --- Tested and rejected (see header): --spec-type draft-mtp (no MTP tensors in
#     this quant), --spec-type none (2.2x slower on code), long ngram drafts 48/64,
#     -ngl 99 (OOM), -ngl 30 (slower), --threads 6 (1.7x slower).
# --- Untested options: --ctx-size 32768 (long docs, +~0.6 GB KV), --ubatch-size 512
#     (prefill is CPU-expert-bound here, unlikely to help), vision via --mmproj.
