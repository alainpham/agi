    # --temp 1.0 \
    # --top-p 0.95 \
    # --top-k 20 \
    # --presence-penalty 1.5 \

/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/occamy-1.0-Q4_K_M.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --reasoning off \
    --reasoning-preserve \
    --load-mode mlock\
    --ctx-size 80000 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --threads 14 \
    --n-gpu-layers 999 --n-cpu-moe 36

