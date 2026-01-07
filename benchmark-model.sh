#!/bin/bash

#===============================================================================
# LLM Model Benchmarking Script for Strix Halo
#===============================================================================
# Benchmarks models with different configurations to find optimal settings
# for AMD Ryzen AI Max+ 395 with 128GB unified memory.
#
# Usage:
#   ./benchmark-model.sh <model_name>                    # Quick benchmark
#   ./benchmark-model.sh <model_name> --full             # Full benchmark suite
#   ./benchmark-model.sh <model_name> --gpu-sweep        # Test GPU layer counts
#   ./benchmark-model.sh <model_name> --batch-sweep      # Test batch sizes
#   ./benchmark-model.sh --list                          # List available models
#===============================================================================

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$SCRIPT_DIR/models}"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/benchmarks}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/model-configs.json}"
LLAMA_BENCH="${LLAMA_BENCH:-$HOME/.local/bin/llama-bench}"
LLAMA_CLI="${LLAMA_CLI:-$HOME/.local/bin/llama-cli}"

# Default benchmark parameters
DEFAULT_PROMPT_TOKENS=512
DEFAULT_GEN_TOKENS=128
DEFAULT_THREADS=16
DEFAULT_REPETITIONS=3

# GPU layer test values (for sweep)
GPU_LAYERS_TEST=(0 20 30 40 50 60 70 80 999)

# Batch size test values (for sweep)
BATCH_SIZES_TEST=(128 256 512 1024 2048)

# Context sizes to test
CTX_SIZES_TEST=(2048 4096 8192)

#===============================================================================
# ROCm/GPU Environment
#===============================================================================

setup_environment() {
    [[ -f "$HOME/.rocm-env.sh" ]] && source "$HOME/.rocm-env.sh"
    export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
    export HSA_ENABLE_SDMA=0
    export GPU_MAX_HEAP_SIZE=100
    export GPU_MAX_ALLOC_PERCENT=100
    export GPU_SINGLE_ALLOC_PERCENT=100
    export GPU_FORCE_64BIT_PTR=1
    export HIP_VISIBLE_DEVICES=0
    export HSA_OVERRIDE_GFX_VERSION=11.5.1
}

#===============================================================================
# Model Configurations (same as start-llm-server.sh)
#===============================================================================

declare -A MODELS

load_models() {
    # Massive models
    MODELS["qwen3-235b"]="$MODELS_DIR/massive/qwen3-235b/UD-Q3_K_XL/Qwen3-235B-A22B-Instruct-2507-UD-Q3_K_XL-00001-of-00003.gguf|60"
    MODELS["qwen3-235b-thinking"]="$MODELS_DIR/massive/qwen3-235b-thinking/Q3_K_M/Qwen3-235B-A22B-Thinking-2507-Q3_K_M-00001-of-00003.gguf|50"
    MODELS["mistral-large-123b"]="$MODELS_DIR/massive/mistral-large-123b/Mistral-Large-Instruct-2407-Q3_K_L/Mistral-Large-Instruct-2407-Q3_K_L-00001-of-00002.gguf|60"
    MODELS["llama-4-scout"]="$MODELS_DIR/massive/llama-4-scout/Q4_K_M/Llama-4-Scout-17B-16E-Instruct-Q4_K_M-00001-of-00002.gguf|999"

    # Large models
    MODELS["codellama-70b"]="$MODELS_DIR/coding/codellama-70b/codellama-70b-instruct.Q4_K_M.gguf|999"
    MODELS["command-r-plus"]="$MODELS_DIR/specialized/command-r-plus/c4ai-command-r-plus-08-2024-Q3_K_M/c4ai-command-r-plus-08-2024-Q3_K_M-00001-of-00002.gguf|60"

    # Balanced models
    MODELS["qwen2.5-32b"]="$MODELS_DIR/balanced/qwen2.5-32b/Qwen2.5-32B-Instruct-Q4_K_M.gguf|999"
    MODELS["deepseek-r1-32b"]="$MODELS_DIR/balanced/deepseek-r1-32b/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf|999"
    MODELS["gemma-2-27b"]="$MODELS_DIR/balanced/gemma-2-27b/gemma-2-27b-it-Q4_K_M.gguf|999"
    MODELS["mistral-small-24b"]="$MODELS_DIR/balanced/mistral-small-24b/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf|999"
    MODELS["qwen2.5-14b"]="$MODELS_DIR/balanced/qwen2.5-14b/Qwen2.5-14B-Instruct-Q5_K_M.gguf|999"

    # Coding models
    MODELS["qwen2.5-coder-32b"]="$MODELS_DIR/coding/qwen2.5-coder-32b/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf|999"
    MODELS["qwen2.5-coder-7b"]="$MODELS_DIR/coding/qwen2.5-coder-7b/Qwen2.5-Coder-7B-Instruct-Q5_K_M.gguf|999"
    MODELS["deepseek-coder-v2-16b"]="$MODELS_DIR/coding/deepseek-coder-v2-16b/DeepSeek-Coder-V2-Lite-Instruct-Q5_K_M.gguf|999"

    # Fast models
    MODELS["qwen2.5-7b"]="$MODELS_DIR/fast/qwen2.5-7b/Qwen2.5-7B-Instruct-Q5_K_M.gguf|999"
    MODELS["llama-3.1-8b"]="$MODELS_DIR/fast/llama-3.1-8b/Meta-Llama-3.1-8B-Instruct-Q5_K_M.gguf|999"
    MODELS["gemma-2-9b"]="$MODELS_DIR/fast/gemma-2-9b/gemma-2-9b-it-Q5_K_M.gguf|999"
    MODELS["mistral-7b"]="$MODELS_DIR/fast/mistral-7b/Mistral-7B-Instruct-v0.3-Q5_K_M.gguf|999"
    MODELS["llama-3.2-3b"]="$MODELS_DIR/fast/llama-3.2-3b/Llama-3.2-3B-Instruct-Q6_K_L.gguf|999"

    # Specialized
    MODELS["phi-4"]="$MODELS_DIR/specialized/phi-4/phi-4-Q5_K_M.gguf|999"
    MODELS["solar-10.7b"]="$MODELS_DIR/specialized/solar-10.7b/solar-10.7b-instruct-v1.0.Q5_K_M.gguf|999"
}

#===============================================================================
# Colors and Output
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════════════${NC}\n"
}

print_subheader() {
    echo -e "\n${BLUE}── $1 ──${NC}\n"
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

#===============================================================================
# Benchmarking Functions
#===============================================================================

run_llama_bench() {
    local model_path="$1"
    local gpu_layers="$2"
    local batch_size="${3:-512}"
    local prompt_tokens="${4:-$DEFAULT_PROMPT_TOKENS}"
    local gen_tokens="${5:-$DEFAULT_GEN_TOKENS}"
    local reps="${6:-$DEFAULT_REPETITIONS}"

    "$LLAMA_BENCH" \
        -m "$model_path" \
        -ngl "$gpu_layers" \
        -t "$DEFAULT_THREADS" \
        -b "$batch_size" \
        -ub "$batch_size" \
        -p "$prompt_tokens" \
        -n "$gen_tokens" \
        -r "$reps" \
        -fa 1 \
        -o json 2>/dev/null
}

parse_bench_results() {
    local json="$1"

    # Extract key metrics using jq or grep/awk
    if command -v jq &>/dev/null; then
        local pp_avg=$(echo "$json" | jq -r '.[0].avg_ts // 0' 2>/dev/null)
        local tg_avg=$(echo "$json" | jq -r '.[1].avg_ts // 0' 2>/dev/null)
        echo "$pp_avg|$tg_avg"
    else
        # Fallback parsing
        echo "0|0"
    fi
}

benchmark_single() {
    local model_name="$1"
    local gpu_layers="$2"
    local batch_size="${3:-512}"
    local ctx_size="${4:-4096}"

    local config="${MODELS[$model_name]}"
    if [[ -z "$config" ]]; then
        print_error "Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r model_path default_gpu <<< "$config"

    if [[ ! -f "$model_path" ]]; then
        print_error "Model file not found: $model_path"
        return 1
    fi

    local model_size=$(du -h "$model_path" 2>/dev/null | awk '{print $1}')

    echo -e "${BOLD}Configuration:${NC}"
    echo "  Model: $model_name ($model_size)"
    echo "  GPU Layers: $gpu_layers"
    echo "  Batch Size: $batch_size"
    echo "  Threads: $DEFAULT_THREADS"
    echo ""

    print_info "Running benchmark (this may take a few minutes)..."

    local start_time=$(date +%s)
    local result=$(run_llama_bench "$model_path" "$gpu_layers" "$batch_size")
    local end_time=$(date +%s)
    local duration=$((end_time - start_time))

    if [[ -z "$result" || "$result" == "null" ]]; then
        print_error "Benchmark failed - model may be too large for this GPU layer config"
        return 1
    fi

    echo "$result"
}

benchmark_gpu_sweep() {
    local model_name="$1"
    local config="${MODELS[$model_name]}"

    if [[ -z "$config" ]]; then
        print_error "Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r model_path default_gpu <<< "$config"

    print_header "GPU Layer Sweep: $model_name"

    local results_file="$RESULTS_DIR/${model_name}_gpu_sweep_$(date +%Y%m%d_%H%M%S).csv"
    mkdir -p "$RESULTS_DIR"

    echo "gpu_layers,pp_tokens_per_sec,tg_tokens_per_sec,status" > "$results_file"

    printf "%-12s %-20s %-20s %-10s\n" "GPU_LAYERS" "PROMPT (tok/s)" "GENERATION (tok/s)" "STATUS"
    printf "%-12s %-20s %-20s %-10s\n" "----------" "--------------" "------------------" "------"

    for ngl in "${GPU_LAYERS_TEST[@]}"; do
        echo -n "Testing ngl=$ngl... "

        local result=$(run_llama_bench "$model_path" "$ngl" 512 512 64 2)

        if [[ -n "$result" && "$result" != "null" ]]; then
            local pp=$(echo "$result" | jq -r '.[0].avg_ts // 0' 2>/dev/null)
            local tg=$(echo "$result" | jq -r '.[1].avg_ts // 0' 2>/dev/null)

            if [[ "$pp" != "0" && "$pp" != "null" ]]; then
                printf "\r%-12s %-20.2f %-20.2f %-10s\n" "$ngl" "$pp" "$tg" "OK"
                echo "$ngl,$pp,$tg,OK" >> "$results_file"
            else
                printf "\r%-12s %-20s %-20s %-10s\n" "$ngl" "-" "-" "FAILED"
                echo "$ngl,0,0,FAILED" >> "$results_file"
            fi
        else
            printf "\r%-12s %-20s %-20s %-10s\n" "$ngl" "-" "-" "OOM"
            echo "$ngl,0,0,OOM" >> "$results_file"
        fi
    done

    echo ""
    print_success "Results saved to: $results_file"
}

benchmark_batch_sweep() {
    local model_name="$1"
    local gpu_layers="${2:-999}"
    local config="${MODELS[$model_name]}"

    if [[ -z "$config" ]]; then
        print_error "Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r model_path default_gpu <<< "$config"
    [[ "$gpu_layers" == "default" ]] && gpu_layers="$default_gpu"

    print_header "Batch Size Sweep: $model_name (ngl=$gpu_layers)"

    local results_file="$RESULTS_DIR/${model_name}_batch_sweep_$(date +%Y%m%d_%H%M%S).csv"
    mkdir -p "$RESULTS_DIR"

    echo "batch_size,pp_tokens_per_sec,tg_tokens_per_sec,status" > "$results_file"

    printf "%-12s %-20s %-20s %-10s\n" "BATCH_SIZE" "PROMPT (tok/s)" "GENERATION (tok/s)" "STATUS"
    printf "%-12s %-20s %-20s %-10s\n" "----------" "--------------" "------------------" "------"

    for bs in "${BATCH_SIZES_TEST[@]}"; do
        echo -n "Testing batch=$bs... "

        local result=$(run_llama_bench "$model_path" "$gpu_layers" "$bs" 512 64 2)

        if [[ -n "$result" && "$result" != "null" ]]; then
            local pp=$(echo "$result" | jq -r '.[0].avg_ts // 0' 2>/dev/null)
            local tg=$(echo "$result" | jq -r '.[1].avg_ts // 0' 2>/dev/null)

            if [[ "$pp" != "0" && "$pp" != "null" ]]; then
                printf "\r%-12s %-20.2f %-20.2f %-10s\n" "$bs" "$pp" "$tg" "OK"
                echo "$bs,$pp,$tg,OK" >> "$results_file"
            else
                printf "\r%-12s %-20s %-20s %-10s\n" "$bs" "-" "-" "FAILED"
                echo "$bs,0,0,FAILED" >> "$results_file"
            fi
        else
            printf "\r%-12s %-20s %-20s %-10s\n" "$bs" "-" "-" "OOM"
            echo "$bs,0,0,OOM" >> "$results_file"
        fi
    done

    echo ""
    print_success "Results saved to: $results_file"
}

benchmark_quick() {
    local model_name="$1"
    local config="${MODELS[$model_name]}"

    if [[ -z "$config" ]]; then
        print_error "Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r model_path default_gpu <<< "$config"

    print_header "Quick Benchmark: $model_name"

    local model_size=$(du -h "$model_path" 2>/dev/null | awk '{print $1}')
    echo "Model: $(basename "$model_path")"
    echo "Size: $model_size"
    echo "GPU Layers: $default_gpu"
    echo "Threads: $DEFAULT_THREADS"
    echo ""

    print_info "Running benchmark..."

    local result=$("$LLAMA_BENCH" \
        -m "$model_path" \
        -ngl "$default_gpu" \
        -t "$DEFAULT_THREADS" \
        -b 512 \
        -ub 512 \
        -p 512 \
        -n 128 \
        -r 3 \
        -fa 1 \
        2>&1)

    echo ""
    echo "$result"

    # Save results
    local results_file="$RESULTS_DIR/${model_name}_quick_$(date +%Y%m%d_%H%M%S).txt"
    mkdir -p "$RESULTS_DIR"
    echo "$result" > "$results_file"
    echo ""
    print_success "Results saved to: $results_file"
}

benchmark_full() {
    local model_name="$1"

    print_header "Full Benchmark Suite: $model_name"

    echo "This will run multiple benchmark configurations."
    echo "Estimated time: 15-30 minutes depending on model size."
    echo ""

    # Quick benchmark first
    benchmark_quick "$model_name"

    # GPU layer sweep
    benchmark_gpu_sweep "$model_name"

    # Batch size sweep with optimal GPU layers
    local config="${MODELS[$model_name]}"
    IFS='|' read -r model_path default_gpu <<< "$config"
    benchmark_batch_sweep "$model_name" "$default_gpu"

    print_header "Benchmark Complete"
    echo "Results saved in: $RESULTS_DIR/"
    ls -la "$RESULTS_DIR"/${model_name}_* 2>/dev/null
}

save_config() {
    local model_name="$1"
    local gpu_layers="$2"
    local pp_speed="$3"
    local tg_speed="$4"
    local memory_gb="$5"
    local ctx_size="${6:-4096}"
    local batch_size="${7:-512}"

    # Create config file if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << 'INITEOF'
{
  "version": "1.0",
  "description": "Optimized model configurations for Strix Halo (AMD Ryzen AI Max+ 395)",
  "defaults": {
    "threads": 16,
    "batch_size": 512,
    "ctx_size": 4096
  },
  "models": {}
}
INITEOF
    fi

    local date_str=$(date +%Y-%m-%d)
    local temp_file=$(mktemp)

    # Update the config file using jq
    jq --arg name "$model_name" \
       --argjson gpu "$gpu_layers" \
       --argjson ctx "$ctx_size" \
       --argjson batch "$batch_size" \
       --argjson pp "${pp_speed:-0}" \
       --argjson tg "${tg_speed:-0}" \
       --argjson mem "${memory_gb:-0}" \
       --arg date "$date_str" \
       '.models[$name] = {
          "gpu_layers": $gpu,
          "ctx_size": $ctx,
          "batch_size": $batch,
          "benchmark": {
            "pp_tokens_per_sec": $pp,
            "tg_tokens_per_sec": $tg,
            "memory_gb": $mem,
            "date": $date
          }
        }' "$CONFIG_FILE" > "$temp_file" && mv "$temp_file" "$CONFIG_FILE"

    print_success "Configuration saved to: $CONFIG_FILE"
}

get_saved_config() {
    local model_name="$1"

    if [[ -f "$CONFIG_FILE" ]]; then
        jq -r --arg name "$model_name" '.models[$name] // empty' "$CONFIG_FILE" 2>/dev/null
    fi
}

find_optimal_config() {
    local model_name="$1"

    print_header "Finding Optimal Configuration: $model_name"

    local config="${MODELS[$model_name]}"
    if [[ -z "$config" ]]; then
        print_error "Unknown model: $model_name"
        return 1
    fi

    IFS='|' read -r model_path default_gpu <<< "$config"

    local best_ngl=0
    local best_tg=0
    local best_pp=0

    print_info "Testing GPU layer configurations..."
    echo ""

    for ngl in 20 30 40 50 60 70 80 999; do
        echo -n "  Testing ngl=$ngl... "

        local result=$(run_llama_bench "$model_path" "$ngl" 512 256 32 1 2>/dev/null)

        if [[ -n "$result" && "$result" != "null" ]]; then
            local tg=$(echo "$result" | jq -r '.[1].avg_ts // 0' 2>/dev/null)
            local pp=$(echo "$result" | jq -r '.[0].avg_ts // 0' 2>/dev/null)

            if [[ "$tg" != "0" && "$tg" != "null" && -n "$tg" ]]; then
                echo "tg=$tg tok/s"

                # Compare using awk to avoid bc issues
                if awk "BEGIN {exit !($tg > $best_tg)}"; then
                    best_tg=$tg
                    best_pp=$pp
                    best_ngl=$ngl
                fi
            else
                echo "failed"
            fi
        else
            echo "OOM"
        fi
    done

    if [[ "$best_ngl" -eq 0 ]]; then
        print_error "Could not find a working configuration"
        return 1
    fi

    echo ""
    print_info "Running final benchmark with optimal settings..."

    # Run a proper benchmark with the best config
    local final_result=$(run_llama_bench "$model_path" "$best_ngl" 512 512 128 2 2>/dev/null)
    if [[ -n "$final_result" && "$final_result" != "null" ]]; then
        best_pp=$(echo "$final_result" | jq -r '.[0].avg_ts // 0' 2>/dev/null)
        best_tg=$(echo "$final_result" | jq -r '.[1].avg_ts // 0' 2>/dev/null)
    fi

    # Estimate memory usage (rough calculation)
    local model_size_gb=$(du -BG "$model_path" 2>/dev/null | awk '{print $1}' | tr -d 'G')
    local est_memory=$((model_size_gb + 5))  # Add overhead

    echo ""
    print_success "Optimal configuration found:"
    echo "  GPU Layers: $best_ngl"
    echo "  Prompt Processing: $best_pp tok/s"
    echo "  Token Generation: $best_tg tok/s"
    echo "  Estimated Memory: ~${est_memory}GB"
    echo ""

    # Save to config file
    save_config "$model_name" "$best_ngl" "$best_pp" "$best_tg" "$est_memory" 4096 512

    echo ""
    echo "Recommended setting for start-llm-server.sh:"
    echo "  MODELS[\"$model_name\"]=\"$model_path|$best_ngl|4096|\""
}

list_models() {
    print_header "Available Models for Benchmarking"

    printf "%-25s %-12s %s\n" "MODEL" "GPU_LAYERS" "SIZE"
    printf "%-25s %-12s %s\n" "-----" "----------" "----"

    for model_name in $(echo "${!MODELS[@]}" | tr ' ' '\n' | sort); do
        IFS='|' read -r model_path default_gpu <<< "${MODELS[$model_name]}"
        local size="-"
        [[ -f "$model_path" ]] && size=$(du -h "$model_path" 2>/dev/null | awk '{print $1}')
        printf "%-25s %-12s %s\n" "$model_name" "$default_gpu" "$size"
    done
}

compare_models() {
    print_header "Model Comparison Benchmark"

    local models_to_test=("$@")
    [[ ${#models_to_test[@]} -eq 0 ]] && models_to_test=("qwen2.5-7b" "llama-3.1-8b" "mistral-7b")

    local results_file="$RESULTS_DIR/comparison_$(date +%Y%m%d_%H%M%S).csv"
    mkdir -p "$RESULTS_DIR"

    echo "model,gpu_layers,pp_tokens_per_sec,tg_tokens_per_sec" > "$results_file"

    printf "%-25s %-12s %-15s %-15s\n" "MODEL" "GPU_LAYERS" "PP (tok/s)" "TG (tok/s)"
    printf "%-25s %-12s %-15s %-15s\n" "-----" "----------" "----------" "----------"

    for model_name in "${models_to_test[@]}"; do
        local config="${MODELS[$model_name]}"
        [[ -z "$config" ]] && continue

        IFS='|' read -r model_path default_gpu <<< "$config"
        [[ ! -f "$model_path" ]] && continue

        echo -n "Testing $model_name... "

        local result=$(run_llama_bench "$model_path" "$default_gpu" 512 512 64 2 2>/dev/null)

        if [[ -n "$result" && "$result" != "null" ]]; then
            local pp=$(echo "$result" | jq -r '.[0].avg_ts // 0' 2>/dev/null)
            local tg=$(echo "$result" | jq -r '.[1].avg_ts // 0' 2>/dev/null)

            if [[ "$pp" != "0" && "$pp" != "null" ]]; then
                printf "\r%-25s %-12s %-15.2f %-15.2f\n" "$model_name" "$default_gpu" "$pp" "$tg"
                echo "$model_name,$default_gpu,$pp,$tg" >> "$results_file"
            else
                printf "\r%-25s %-12s %-15s %-15s\n" "$model_name" "$default_gpu" "FAILED" "FAILED"
            fi
        else
            printf "\r%-25s %-12s %-15s %-15s\n" "$model_name" "$default_gpu" "OOM" "OOM"
        fi
    done

    echo ""
    print_success "Comparison saved to: $results_file"
}

show_help() {
    echo "LLM Model Benchmarking Script for Strix Halo"
    echo ""
    echo "Usage: $0 <model_name|command> [options]"
    echo ""
    echo "Commands:"
    echo "  <model_name>              Quick benchmark with default settings"
    echo "  <model_name> --full       Full benchmark suite (GPU sweep + batch sweep)"
    echo "  <model_name> --gpu-sweep  Test different GPU layer counts"
    echo "  <model_name> --batch-sweep Test different batch sizes"
    echo "  <model_name> --optimize   Find optimal GPU layer configuration"
    echo "  --list                    List available models"
    echo "  --compare [models...]     Compare multiple models"
    echo "  --help                    Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 qwen3-235b-thinking                    # Quick benchmark"
    echo "  $0 qwen3-235b-thinking --gpu-sweep        # Test GPU layer counts"
    echo "  $0 qwen3-235b-thinking --optimize         # Find best config"
    echo "  $0 --compare qwen2.5-7b llama-3.1-8b      # Compare models"
    echo ""
    echo "Results are saved to: $RESULTS_DIR/"
}

#===============================================================================
# Main
#===============================================================================

main() {
    setup_environment
    load_models

    local command="${1:-help}"

    case "$command" in
        --list|-l)
            list_models
            ;;
        --compare|-c)
            shift
            compare_models "$@"
            ;;
        --help|-h)
            show_help
            ;;
        *)
            # Model name provided
            local model_name="$1"
            local option="${2:-quick}"

            if [[ -z "${MODELS[$model_name]}" ]]; then
                print_error "Unknown model: $model_name"
                echo ""
                echo "Available models:"
                list_models
                exit 1
            fi

            case "$option" in
                --full|-f)
                    benchmark_full "$model_name"
                    ;;
                --gpu-sweep|--gpu)
                    benchmark_gpu_sweep "$model_name"
                    ;;
                --batch-sweep|--batch)
                    benchmark_batch_sweep "$model_name" "${3:-default}"
                    ;;
                --optimize|-o)
                    find_optimal_config "$model_name"
                    ;;
                *)
                    benchmark_quick "$model_name"
                    ;;
            esac
            ;;
    esac
}

main "$@"
