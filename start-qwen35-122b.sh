#!/bin/bash
# Qwen 3.5 122B-A10B MXFP4 - optimized for Strix Halo APU (gfx1151)
# MoE model: 122B total, 10B active per token
# 49/49 GPU layers = fully offloaded
# GPU memory: ~70 GiB
# Binary: Lychee-Technology b8182 (pre-built for gfx1151, ROCm 7.2)

export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export LD_LIBRARY_PATH=$HOME/workspace/.local/bin/llama-lychee:/opt/rocm-7.2.0/lib

MODEL="$HOME/workspace/aimodels/massive/qwen3.5-122b-a10b/Qwen3.5-122B-A10B-MXFP4_MOE-00001-of-00003.gguf"
SERVER="$HOME/workspace/.local/bin/llama-lychee/llama-server"
PORT=8001

exec "$SERVER" \
  --model "$MODEL" \
  --host 0.0.0.0 \
  --port "$PORT" \
  --n-gpu-layers 999 \
  --ctx-size 262144 \
  --parallel 1 \
  --batch-size 2048 \
  --ubatch-size 512 \
  --threads 16 \
  --no-mmap \
  --jinja \
  --metrics \
  --alias qwen3.5-122b \
  --reasoning-budget 0
