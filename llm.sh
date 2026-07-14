#!/bin/bash
cd /home/user/agi/llama.cpp/build/bin
./llama-server \
    --models-preset \
        /home/user/agi/config/llama-server/models.ini \
    --host 0.0.0.0 \
    --port 8080