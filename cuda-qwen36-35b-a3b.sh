    # --temp 0.6 \
    # --top-p 0.95 \
    # --top-k 20 \
    # --min-p 0.0 \
    # --presence-penalty 0.0 \
    # --repeat-penalty 1.0 \

    # --temp 1.0 \
    # --top-p 0.95 \
    # --top-k 20 \
    # --min-p 0.0 \
    # --presence-penalty 1.5 \
    # --repeat-penalty 1.0 \

/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
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
    --spec-type draft-mtp --spec-draft-n-max 2 \
    --temp 1.0 \
    --top-p 0.95 \
    --top-k 20 \
    --min-p 0.0 \
    --presence-penalty 1.5 \
    --repeat-penalty 1.0 \
    --n-gpu-layers 999 --n-cpu-moe 40
    

