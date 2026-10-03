/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/Qwen3.8-27B-UD-IQ4_XS.gguf \
    --model-draft /home/user/aimodels/llms/mtp-Qwen3.8-27B-Q4_0.gguf
    --host 0.0.0.0 \
    --port 8080 \
    --reasoning on \
    --load-mode mlock\
    --ctx-size 32768 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --threads 6 \
    --temp 1.0 --top-p 0.95 --top-k 20 --min-p 0.0 \
    --spec-type draft-mtp --spec-draft-n-max 2 \
    --n-gpu-layers 999
    
