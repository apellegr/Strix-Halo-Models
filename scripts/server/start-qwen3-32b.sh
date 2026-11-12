#!/bin/bash
# Qwen3-32B (dense, general instruction-following — used for family-assistant email triage) - Strix Halo APU (gfx1151)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then source "$REPO_DIR/.env"; fi
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
PORT="${PORT:-8002}"
MODEL="$MODELS_DIR/balanced/qwen3-32b/Qwen3-32B-Q4_K_M.gguf"
if [[ ! -f "$MODEL" ]]; then echo "ERROR: model not found: $MODEL" >&2; exit 1; fi
exec "$LLAMA_SERVER" \
  --model "$MODEL" \
  --host 0.0.0.0 --port "$PORT" \
  --n-gpu-layers 999 \
  --ctx-size 16384 \
  --parallel 1 \
  --batch-size 2048 --ubatch-size 512 \
  --threads 16 --no-mmap --jinja --metrics \
  --alias qwen3-32b --flash-attn on --reasoning-budget 0
