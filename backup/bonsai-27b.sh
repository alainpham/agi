/home/$USER/agi/prismaml/llama.cpp/build/bin/llama-server \
    -m ~/aimodels/llms/Bonsai-27B-Q1_0.gguf \
    --temp 0.7 \
    --top-p 0.95 \
    --top-k 20 \
    --n-gpu-layers 999 \
    --mlock \
    --no-mmap \
    --ctx-size 80000 \
    --jinja \
    --batch-size 2048 \
    --ubatch-size 512 \
    --flash-attn on \
    --parallel 1 \
    --threads 14 \
    --cache-type-k q4_0 \
    --cache-type-v q4_0 \
    --host 0.0.0.0 \
    --port 8080

    # -m ~/aimodels/llms/Bonsai-27B-Q1_0.gguf \
    # --alias bonsai-27b \
    # --temp 0.7 \
    # --top-p 0.95 \
    # --top-k 20 \
    # --n-gpu-layers 999 \
    # --mlock \
    # --no-mmap \
    # --ctx-size 80000 \
    # --no-kv-offload \
    # --parallel 1 \
    # --threads 14 \
    # --cache-type-k q4_0 \
    # --cache-type-v q4_0 \
    # --host 0.0.0.0 \
    # --port 8080