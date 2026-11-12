#!/bin/bash
# Qwen3.8-27B (general intelligence, dense) - Strix Halo APU (gfx1151)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then source "$REPO_DIR/.env"; fi
# llama.cpp b12259 (release asset: ubuntu-rocm-10.0) must run on the ROCm 10.0 runtime it was built for.
# A mismatched runtime (e.g. /opt/rocm-7.2.0) loads fine but corrupts long-prompt output. Set 2026-11-12.
LLAMA_BUILD="$HOME/workspace/.local/bin/llama-mainline-b12259/llama-b12259"
ROCM_LIB="$HOME/rocm10/opt/rocm/core-10.0/lib"
LLAMA_SERVER="$LLAMA_BUILD/llama-server"
export LD_LIBRARY_PATH="$LLAMA_BUILD:$ROCM_LIB"
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
PORT="${PORT:-8001}"
MODEL="$MODELS_DIR/general/qwen3.8-27b/Qwen3.8-27B-UD-Q4_K_XL.gguf"
if [[ ! -f "$MODEL" ]]; then echo "ERROR: model not found: $MODEL" >&2; exit 1; fi
if [[ ! -x "$LLAMA_SERVER" ]]; then echo "ERROR: llama-server not found: $LLAMA_SERVER" >&2; exit 1; fi
exec "$LLAMA_SERVER" \
  --model "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  --n-gpu-layers 999 \
  --ctx-size 262144 \
  --parallel 1 \
  --batch-size 4096 --ubatch-size 2048 \
  --threads 16 --load-mode none --jinja --metrics \
  --alias qwen3.8-27b --flash-attn on \
  --spec-type draft-mtp \
  --cache-type-k q8_0 --cache-type-v q8_0 \
  --chat-template-kwargs '{"enable_thinking":true,"reasoning_effort":"low"}'
