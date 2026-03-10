#!/bin/bash
# Qwen 2.5 Coder 32B Instruct - optimized for Strix Halo APU (gfx1151)
# 80 GPU layers offloaded, 32K context
#
# Configuration:
#   MODELS_DIR     - Base directory for model files (default: $HOME/llm-models)
#   LLAMA_SERVER   - Path to llama-server binary (default: llama-server on PATH)
#   PORT           - Listening port (default: 8001)
#
# You can set these in a .env file next to this script or export them beforehand.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
if [[ -f "$REPO_DIR/.env" ]]; then
  # shellcheck disable=SC1091
  source "$REPO_DIR/.env"
fi

# ROCm environment for Strix Halo (gfx1151)
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1

MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"
PORT="${PORT:-8001}"

MODEL="$MODELS_DIR/coding/qwen2.5-coder-32b/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf"

if [[ ! -f "$MODEL" ]]; then
  echo "ERROR: Model file not found: $MODEL" >&2
  echo "Set MODELS_DIR to the directory containing your models, or run download_strix_halo_models.sh to fetch them." >&2
  exit 1
fi

exec "$LLAMA_SERVER" \
  --model "$MODEL" \
  --host 0.0.0.0 \
  --port "$PORT" \
  --n-gpu-layers 80 \
  --ctx-size 32768 \
  --threads 16 \
  --batch-size 1024 \
  --no-mmap \
  --metrics \
  --alias qwen2.5-coder-32b
