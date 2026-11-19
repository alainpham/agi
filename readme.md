# Running local ai

## llama.cpp

```sh
git clone https://github.com/ggml-org/llama.cpp.git
cd llama.cpp
cmake -B build -DGGML_VULKAN=ON
cmake --build build --config Release

./llama-server -hf bartowski/Qwen_Qwen3.6-35B-A3B-GGUF:Q4_K_M \
    -ngl 999 \
    --n-cpu-moe 36 \
    --no-mmap \
    --mlock \
    --ctx-size 128000
```


## audio.cpp

Run the interactive installer (CUDA when NVIDIA is detected, Vulkan otherwise,
including AMD GPUs):

```sh
./install-audio-cpp.sh
```

Requires Git, CMake >= 3.20, GCC >= 13 and the selected GPU toolchain: CUDA
Toolkit >= 12 for CUDA, Vulkan headers/loader and `glslc` for Vulkan, or ROCm
for HIP. The installer uses the [upstream Linux build helper](https://github.com/0xShug0/audio.cpp/blob/main/docs/build/linux.md)
to compile the CLI and server in Release mode with embedded model specs.

To select a backend explicitly:

```sh
AUDIO_BACKEND=cuda ./install-audio-cpp.sh
AUDIO_BACKEND=vulkan ./install-audio-cpp.sh
AUDIO_BACKEND=hip ./install-audio-cpp.sh
# Optional HIP architecture override (otherwise detected by the build helper):
AUDIO_BACKEND=hip GPU_TARGETS=gfx1151 ./install-audio-cpp.sh
```

Binaries are in `~/agi/audio.cpp/build/linux-<backend>-release/bin`.
Check available devices with `audiocpp_cli --list-devices` in that directory.
CUDA builds target the local GPU by default; set `CUDA_ARCH` to override this.
Set `JOBS` to limit build parallelism, or `AUDIO_REPO` to use another repository.
Model weights must be downloaded separately; see the [audio.cpp documentation](https://github.com/0xShug0/audio.cpp).

## Chatterbox

change in env var of docker-compose-rocm.yml

```sh
    environment:
      - HSA_OVERRIDE_GFX_VERSION=11.0.0
```

```sh
git clone https://github.com/devnen/Chatterbox-TTS-Server.git
docker compose -f docker-compose-rocm.yml up -d --build
docker compose -f docker-compose-rocm.yml up -d
```

## kokoro tts

```sh
docker run --name kokoro --device=/dev/kfd --device=/dev/dri -p 8880:8880 ghcr.io/remsky/kokoro-fastapi-rocm:latest
```

## stable diffusion cpp

```sh
export PATH=$PATH:/home/user/workspaces/localai/stable-diffusion.cpp/build/bin

export CP_FOLDER=/home/user/aimodels/checkpoints

export DF_FOLDER=/home/user/aimodels/diffusion_models

export VAE_FOLDER=/home/user/aimodels/vae

export LLM_FOLDER=/home/user/aimodels/text_encoders


```

### qwen image

```sh
sd-server \
  --diffusion-model $DF_FOLDER/Qwen_Image-Q4_K_M.gguf \
  --vae $VAE_FOLDER/qwen_image_vae.safetensors \
  --llm $LLM_FOLDER/Qwen2.5-VL-7B-Instruct.Q4_K_M.gguf
```

### sd 1.5

```sh
sd-server -m $CP_FOLDER/epicrealism_naturalSinRC1VAE.safetensors
sd-server -m $CP_FOLDER/dreamshaper_8.safetensors

```

# Comfy ui ROCM

https://rocm.blogs.amd.com/artificial-intelligence/comfyui-radeon-9000/README.html
```

```
