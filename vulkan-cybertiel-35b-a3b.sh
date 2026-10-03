/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/Cyber-Tiel-Coder-35B-A3B-MTP-UD-Q4_K_XL.gguf \
    --mmproj /home/user/aimodels/llms/mmproj-Q8_0.gguf \
    --no-mmproj-offload \
    --host 0.0.0.0 \
    --port 8080 \
    --reasoning on \
    --load-mode mlock\
    --ctx-size 81920 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --threads 6 \
    --spec-type draft-mtp --spec-draft-n-max 2 \
    --temp 0.6 --top-p 0.95 --top-k 20 --min-p 0 \
    --n-gpu-layers 999
    

