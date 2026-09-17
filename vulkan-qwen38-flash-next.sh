#!/usr/bin/env bash
# Qwen3.8-Flash-Next -- arch "qwen4exp": 177B total, 512 experts, 10 active (~6B active),
# 48 blocks, hybrid SSM + full attention every 4th layer, hyper-connections, PLE n-gram table.
#
# MEMORY
#   ~54.5 GB of this build MUST stay resident (experts + attention); this box has 61.5 GiB.
#   ~38.4 GB is the PLE n-gram lookup table and is meant to live on NVMe, paged in on demand
#   (~2.7 KB per token at a deterministic address). That is what -lm mmap + --lazy-mode on buy.
#   Never --no-mmap / --mlock / -lm dio here: those try to make all 89 GB resident.
#
# -fit off is mandatory: the publisher documents that llama.cpp's automatic parameter fitting
# mis-sizes this architecture and fails to allocate.
#
# WHY -ngl 0 ON A VULKAN BUILD (measured, llama-bench tg128, build 972d2313b)
#   -ngl 999 --cpu-moe -t 12 .... 2.16 t/s   (thrashing: >200k major faults/min)
#   -ngl 999 --cpu-moe -t 6 ..... 2.86 t/s   (35k major faults, RSS squeezed to 47.8 GB)
#   -ngl 0             -t 12 .... 3.18 t/s
#   -ngl 0             -t 4 ..... 3.67 t/s
#   -ngl 0             -t 6 ..... 4.12 t/s   <-- this config, 0 major faults, RSS 53.8 GB
#   The 740M's GTT allocations are *pinned* system RAM stacked on top of the mmap'd weights,
#   which tips the box into eviction. Dropping the iGPU costs nothing on prefill either
#   (pp512: 31.6 t/s on the iGPU vs 31.7 t/s on 4 CPU threads). 4 CUs never paid for themselves.
#
# SPECULATIVE DECODING -- SHORT DRAFTS ONLY ON THIS HARDWARE
#   Measured on a verbatim code-rewrite (ngram-mod's documented best case), tg:
#     spec off ................................ 4.25 t/s
#     n-match 24 n-min 48 n-max 64 (the docs) . 2.19 t/s   <-- 48% SLOWER
#     n-match 24 n-min  8 n-max 16 ............ 4.83 t/s   <-- +14%
#   The docs say "MoEs require long drafts", but that assumes a GPU where prefill is 50-100x
#   decode. Here pp/tg is only ~7.7x, so a 64-token draft batch costs ~8 decode steps and needs
#   ~8 accepted tokens per round just to break even. Short drafts are the only ones that pay.
#   On novel, reasoning-heavy prose (not measured at n-max 16; measured at n-max 64) drafting
#   was a 3-20% loss, so drop the four --spec-* lines if your workload is not code/rewriting.
#
# NOTE: this model's PLE n-grams are unrelated to --spec-type ngram-*. Both are called "n-gram"
# but the first is a weight lookup table inside the model and the second is speculative decoding.
#
# KV at 32k is only ~800 MiB at f16 here (just 12 of 48 layers are full-attention, 2 KV heads of
# 256 dim), and f16 already leaves ~1.7 GiB free with zero paging, so do not bother quantizing it.
#
# --chat-template-kwargs reasoning_effort accepts only xhigh (default), medium, low.

/home/$USER/agi/llama.cpp/build/bin/llama-server \
    -hf AtomicChat/Qwen3.8-Flash-Next-GGUF:Q4_K_M \
    --host 0.0.0.0 \
    --port 8080 \
    --jinja \
    --chat-template-kwargs '{"reasoning_effort":"medium"}' \
    --reasoning-preserve \
    -fit off \
    -ngl 0 \
    -lm mmap \
    --lazy-mode on \
    --cache-ram 0 \
    --ctx-size 32768 \
    --parallel 1 \
    --flash-attn on \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --batch-size 2048 \
    --ubatch-size 512 \
    --threads 6 \
    --threads-batch 6 \
    --spec-type ngram-mod \
    --spec-ngram-mod-n-match 24 \
    --spec-ngram-mod-n-min 8 \
    --spec-ngram-mod-n-max 16 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 0.0 \
    --repeat-penalty 1.0
