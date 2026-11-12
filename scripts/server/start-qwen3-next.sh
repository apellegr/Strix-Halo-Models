#!/bin/bash
# Qwen3-Next-80B-A3B (MoE, 3B active) - Strix Halo APU - bake-off vs GLM-4.7-Flash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then source "$REPO_DIR/.env"; fi
export HSA_ENABLE_SDMA=0 GPU_MAX_HEAP_SIZE=100 GPU_MAX_ALLOC_PERCENT=100 GPU_SINGLE_ALLOC_PERCENT=100 GPU_FORCE_64BIT_PTR=1 HIP_VISIBLE_DEVICES=0 HSA_OVERRIDE_GFX_VERSION=11.5.1
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
PORT="${PORT:-8002}"
MODEL="$MODELS_DIR/large/qwen3-next-80b-a3b/Qwen3-Next-80B-A3B-Instruct-Q4_1-00001-of-00002.gguf"
[[ -f "$MODEL" ]] || { echo "ERROR: model not found: $MODEL" >&2; exit 1; }
exec "$LLAMA_SERVER" --model "$MODEL" --host 0.0.0.0 --port "$PORT" \
  --n-gpu-layers 999 --ctx-size 16384 --parallel 1 --batch-size 2048 --ubatch-size 512 \
  --threads 16 --no-mmap --jinja --metrics --alias qwen3-next-80b --flash-attn on
