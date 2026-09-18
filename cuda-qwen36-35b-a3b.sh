# export LLAMA_CACHE="unsloth/Qwen3.6-35B-A3B-MTP-GGUF"
# ./llama.cpp/llama-server \
#     -hf unsloth/Qwen3.6-35B-A3B-MTP-GGUF:UD-Q4_K_XL \
#     -ngl 99 -c 8192 -fa on -np 1 \
#     --spec-type draft-mtp --spec-draft-n-max 2

/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --reasoning on \
    --reasoning-preserve \
    --load-mode mlock\
    --ctx-size 32768 \
    --cache-type-k q8_0 \
    --cache-type-v q4_0 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --threads 14 \
    --spec-type draft-mtp --spec-draft-n-max 2 \
    --n-gpu-layers 999 --n-cpu-moe 36

