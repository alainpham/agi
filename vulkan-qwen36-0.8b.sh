/home/$USER/agi/llama.cpp/build/bin/llama-server \
    --model /home/user/aimodels/llms/Qwen3.5-0.8B-UD-Q4_K_XL.gguf \
    --mmproj /home/user/aimodels/llms/Qwen3.5-0.8B-mmproj-F16.gguf \
    --host 0.0.0.0 \
    --port 8080 \
    --reasoning off \
    --load-mode mlock\
    --ctx-size 8192 \
    --cache-type-k f16 \
    --cache-type-v f16 \
    --jinja \
    --flash-attn on \
    --parallel 1 \
    --threads 6 \
    --temp 1.0 --top-p 1.0 --top-k 20 --min-p 0 --presence-penalty 2.0 --repeat-penalty 1.0 \
    --n-gpu-layers 999
    

