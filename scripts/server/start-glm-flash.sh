#!/bin/bash
# GLM-4.7-Flash (MoE, agentic/tool-calling) - Strix Halo APU (gfx1151) - family-assistant chat test
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then source "$REPO_DIR/.env"; fi
# llama.cpp b12259 (release asset: ubuntu-rocm-10.0) must run on the ROCm 10.0 runtime it was built for.
# A mismatched runtime (e.g. /opt/rocm-7.2.0) loads fine but corrupts long-prompt output. Set 2026-11-12.
LLAMA_BUILD="$HOME/workspace/.local/bin/llama-mainline-b12259/llama-b12259"
ROCM_LIB="$HOME/rocm10/opt/rocm/core-10.0/lib"
LLAMA_SERVER="$LLAMA_BUILD/llama-server"
export LD_LIBRARY_PATH="$LLAMA_BUILD:$ROCM_LIB"
export HSA_ENABLE_SDMA=0 GPU_MAX_HEAP_SIZE=100 GPU_MAX_ALLOC_PERCENT=100 GPU_SINGLE_ALLOC_PERCENT=100 GPU_FORCE_64BIT_PTR=1 HIP_VISIBLE_DEVICES=0 HSA_OVERRIDE_GFX_VERSION=11.5.1
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
PORT="${PORT:-8002}"
MODEL="$MODELS_DIR/tool-calling/glm-4.7-flash/GLM-4.7-Flash-Q4_K_M.gguf"
[[ -f "$MODEL" ]] || { echo "ERROR: model not found: $MODEL" >&2; exit 1; }
exec "$LLAMA_SERVER" --model "$MODEL" --host 0.0.0.0 --port "$PORT" \
  --n-gpu-layers 999 --ctx-size 16384 --parallel 1 --batch-size 2048 --ubatch-size 512 \
  --threads 16 --load-mode none --jinja --metrics --alias glm-4.7-flash --flash-attn on
