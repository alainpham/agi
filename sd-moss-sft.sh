/home/$USER/agi/stable-diffusion.cpp/build/bin/sd-server \
    --diffusion-model /home/user/aimodels/diffusion_models/MOSS-Image-SFT-Q4_K.gguf  \
    --vae /home/user/aimodels/vae/flux2-vae.safetensors  \
    --llm /home/user/aimodels/text_encoders/Qwen3.5-9B-Q4_K_M.gguf  \
    --tokenizer /home/user/aimodels/tokenizer/tokenizer.json \
    --diffusion-fa --offload-to-cpu -l 0.0.0.0 
