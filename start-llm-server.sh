#!/bin/bash

#===============================================================================
# LLM Server Startup Script for Strix Halo
#===============================================================================
# Optimized for AMD Ryzen AI Max+ 395 with 128GB unified memory
# Uses hybrid CPU+GPU mode with ROCm for best performance
#
# Usage:
#   ./start-llm-server.sh                    # Start default model (Qwen3-235B)
#   ./start-llm-server.sh qwen3-235b         # Start specific model
#   ./start-llm-server.sh stop               # Stop all servers
#   ./start-llm-server.sh status             # Check server status
#   ./start-llm-server.sh list               # List available models
#===============================================================================

# Don't exit on error for status checks
# set -e

#===============================================================================
# Configuration
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODELS_DIR="${MODELS_DIR:-$SCRIPT_DIR/models}"
RUN_DIR="${RUN_DIR:-$HOME/.llm-servers}"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/.local/bin/llama-server}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/model-configs.json}"

# Default server settings
DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT="8081"
DEFAULT_THREADS="16"          # Physical cores (SMT2 system)
DEFAULT_BATCH_SIZE="512"
DEFAULT_CTX_SIZE="4096"

#===============================================================================
# ROCm/GPU Environment for Strix Halo Unified Memory
#===============================================================================

setup_gpu_environment() {
    # Source ROCm environment if available
    [[ -f "$HOME/.rocm-env.sh" ]] && source "$HOME/.rocm-env.sh"

    # Add local lib to library path
    export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"

    # Critical settings for Strix Halo unified memory (GTT)
    export HSA_ENABLE_SDMA=0
    export GPU_MAX_HEAP_SIZE=100
    export GPU_MAX_ALLOC_PERCENT=100
    export GPU_SINGLE_ALLOC_PERCENT=100
    export GPU_FORCE_64BIT_PTR=1
    export HIP_VISIBLE_DEVICES=0
    export HSA_OVERRIDE_GFX_VERSION=11.5.1
}

#===============================================================================
# Model Configurations
# Format: model_path|gpu_layers|ctx_size|extra_args
#===============================================================================

declare -A MODELS

# Massive models (60 GPU layers for hybrid mode)
MODELS["qwen3-235b"]="$MODELS_DIR/massive/qwen3-235b/UD-Q3_K_XL/Qwen3-235B-A22B-Instruct-2507-UD-Q3_K_XL-00001-of-00003.gguf|60|4096|"
MODELS["qwen3-235b-thinking"]="$MODELS_DIR/massive/qwen3-235b-thinking/Q3_K_M/Qwen3-235B-A22B-Thinking-2507-Q3_K_M-00001-of-00003.gguf|50|4096|"
MODELS["mistral-large-123b"]="$MODELS_DIR/massive/mistral-large-123b/Mistral-Large-Instruct-2407-Q3_K_L/Mistral-Large-Instruct-2407-Q3_K_L-00001-of-00002.gguf|60|4096|"
MODELS["llama-4-scout"]="$MODELS_DIR/massive/llama-4-scout/Q4_K_M/Llama-4-Scout-17B-16E-Instruct-Q4_K_M-00001-of-00002.gguf|999|8192|"

# Large models (full GPU offload)
MODELS["codellama-70b"]="$MODELS_DIR/coding/codellama-70b/codellama-70b-instruct.Q4_K_M.gguf|999|4096|"
MODELS["command-r-plus"]="$MODELS_DIR/specialized/command-r-plus/c4ai-command-r-plus-08-2024-Q3_K_M/c4ai-command-r-plus-08-2024-Q3_K_M-00001-of-00002.gguf|60|4096|"

# Balanced models (full GPU offload)
MODELS["qwen2.5-32b"]="$MODELS_DIR/balanced/qwen2.5-32b/Qwen2.5-32B-Instruct-Q4_K_M.gguf|999|8192|"
MODELS["deepseek-r1-32b"]="$MODELS_DIR/balanced/deepseek-r1-32b/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf|999|8192|"
MODELS["gemma-2-27b"]="$MODELS_DIR/balanced/gemma-2-27b/gemma-2-27b-it-Q4_K_M.gguf|999|8192|"
MODELS["mistral-small-24b"]="$MODELS_DIR/balanced/mistral-small-24b/Mistral-Small-24B-Instruct-2501-Q4_K_M.gguf|999|8192|"
MODELS["qwen2.5-14b"]="$MODELS_DIR/balanced/qwen2.5-14b/Qwen2.5-14B-Instruct-Q5_K_M.gguf|999|16384|"

# Coding models
MODELS["qwen2.5-coder-32b"]="$MODELS_DIR/coding/qwen2.5-coder-32b/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf|999|16384|"
MODELS["qwen2.5-coder-7b"]="$MODELS_DIR/coding/qwen2.5-coder-7b/Qwen2.5-Coder-7B-Instruct-Q5_K_M.gguf|999|32768|"
MODELS["deepseek-coder-v2-16b"]="$MODELS_DIR/coding/deepseek-coder-v2-16b/DeepSeek-Coder-V2-Lite-Instruct-Q5_K_M.gguf|999|16384|"

# Fast models (full GPU offload, larger context)
MODELS["qwen2.5-7b"]="$MODELS_DIR/fast/qwen2.5-7b/Qwen2.5-7B-Instruct-Q5_K_M.gguf|999|32768|"
MODELS["llama-3.1-8b"]="$MODELS_DIR/fast/llama-3.1-8b/Meta-Llama-3.1-8B-Instruct-Q5_K_M.gguf|999|32768|"
MODELS["gemma-2-9b"]="$MODELS_DIR/fast/gemma-2-9b/gemma-2-9b-it-Q5_K_M.gguf|999|16384|"
MODELS["mistral-7b"]="$MODELS_DIR/fast/mistral-7b/Mistral-7B-Instruct-v0.3-Q5_K_M.gguf|999|32768|"
MODELS["llama-3.2-3b"]="$MODELS_DIR/fast/llama-3.2-3b/Llama-3.2-3B-Instruct-Q6_K_L.gguf|999|65536|"

# Specialized models
MODELS["phi-4"]="$MODELS_DIR/specialized/phi-4/phi-4-Q5_K_M.gguf|999|16384|"
MODELS["solar-10.7b"]="$MODELS_DIR/specialized/solar-10.7b/solar-10.7b-instruct-v1.0.Q5_K_M.gguf|999|16384|"

# Vision models
MODELS["qwen2.5-vl-7b"]="$MODELS_DIR/vision/qwen2.5-vl-7b/Qwen2.5-VL-7B-Instruct-Q5_K_M.gguf|999|8192|"
MODELS["pixtral-12b"]="$MODELS_DIR/vision/pixtral-12b/mistral-community_pixtral-12b-Q4_K_M.gguf|999|8192|"
MODELS["llava-1.6-7b"]="$MODELS_DIR/vision/llava-1.6-7b/llava-v1.6-mistral-7b.Q5_K_M.gguf|999|8192|"

#===============================================================================
# Colors
#===============================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

#===============================================================================
# Helper Functions
#===============================================================================

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n"
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

get_pid_file() { echo "$RUN_DIR/${1}.pid"; }
get_log_file() { echo "$RUN_DIR/${1}.log"; }

# Get saved optimized config from model-configs.json
# Returns: gpu_layers ctx_size batch_size (space separated)
get_saved_config() {
    local model_name="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi

    # Check if model exists in config file
    if ! jq -e ".models[\"$model_name\"]" "$CONFIG_FILE" >/dev/null 2>&1; then
        return 1
    fi

    # Extract values from config
    local saved_gpu_layers=$(jq -r ".models[\"$model_name\"].gpu_layers // empty" "$CONFIG_FILE")
    local saved_ctx_size=$(jq -r ".models[\"$model_name\"].ctx_size // empty" "$CONFIG_FILE")
    local saved_batch_size=$(jq -r ".models[\"$model_name\"].batch_size // empty" "$CONFIG_FILE")

    if [[ -n "$saved_gpu_layers" ]]; then
        echo "$saved_gpu_layers $saved_ctx_size $saved_batch_size"
        return 0
    fi

    return 1
}

is_running() {
    local pid_file=$(get_pid_file "$1")
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        kill -0 "$pid" 2>/dev/null && return 0
    fi
    return 1
}

#===============================================================================
# Server Management
#===============================================================================

start_model() {
    local model_name="$1"
    local port="${2:-$DEFAULT_PORT}"

    if [[ -z "${MODELS[$model_name]}" ]]; then
        print_error "Unknown model: $model_name"
        echo "Use './start-llm-server.sh list' to see available models"
        return 1
    fi

    if is_running "$model_name"; then
        print_warning "Model '$model_name' is already running"
        return 0
    fi

    # Parse model config
    IFS='|' read -r model_path gpu_layers ctx_size extra_args <<< "${MODELS[$model_name]}"

    # Check for saved optimized config and override defaults
    local is_optimized=""
    local saved_config
    if saved_config=$(get_saved_config "$model_name"); then
        read -r saved_gpu saved_ctx saved_batch <<< "$saved_config"
        if [[ -n "$saved_gpu" ]]; then
            gpu_layers="$saved_gpu"
            [[ -n "$saved_ctx" ]] && ctx_size="$saved_ctx"
            is_optimized="yes"
        fi
    fi

    if [[ ! -f "$model_path" ]]; then
        print_error "Model file not found: $model_path"
        return 1
    fi

    # Setup environment
    setup_gpu_environment

    # Create run directory
    mkdir -p "$RUN_DIR"

    local pid_file=$(get_pid_file "$model_name")
    local log_file=$(get_log_file "$model_name")

    if [[ -n "$is_optimized" ]]; then
        print_header "Starting $model_name (OPTIMIZED)"
        print_success "Using optimized config from model-configs.json"
    else
        print_header "Starting $model_name"
        print_warning "No optimized config found - using defaults"
        print_info "Run: ./benchmark-model.sh $model_name --optimize"
    fi
    print_info "Model: $(basename "$model_path")"
    print_info "GPU Layers: $gpu_layers"
    print_info "Context Size: $ctx_size"
    print_info "Port: $port"
    print_info "Threads: $DEFAULT_THREADS"
    echo ""

    # Start the server
    nohup "$LLAMA_SERVER" \
        --model "$model_path" \
        --host "$DEFAULT_HOST" \
        --port "$port" \
        --n-gpu-layers "$gpu_layers" \
        --ctx-size "$ctx_size" \
        --threads "$DEFAULT_THREADS" \
        --batch-size "$DEFAULT_BATCH_SIZE" \
        --no-mmap \
        --alias "$model_name" \
        $extra_args \
        > "$log_file" 2>&1 &

    local pid=$!
    echo "$pid" > "$pid_file"

    print_info "Started with PID: $pid"
    print_info "Log file: $log_file"
    print_info "Waiting for model to load..."

    # Wait for server to be ready (with timeout)
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://localhost:$port/health" 2>/dev/null | grep -q '"status":"ok"'; then
            echo ""
            print_success "Server ready!"
            print_success "API endpoint: http://localhost:$port/v1"
            echo ""
            echo -e "${CYAN}Open WebUI Configuration:${NC}"
            echo "  URL: http://localhost:$port/v1"
            echo "  API Key: sk-dummy (any value)"
            return 0
        fi

        # Check if process died
        if ! kill -0 "$pid" 2>/dev/null; then
            echo ""
            print_error "Server process died. Check log: $log_file"
            tail -20 "$log_file"
            rm -f "$pid_file"
            return 1
        fi

        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done

    echo ""
    print_warning "Server still loading after ${timeout}s. Check status with: $0 status"
    return 0
}

run_model_foreground() {
    # Run model in foreground (for systemd)
    local model_name="$1"
    local port="${2:-$DEFAULT_PORT}"

    if [[ -z "${MODELS[$model_name]}" ]]; then
        echo "ERROR: Unknown model: $model_name" >&2
        return 1
    fi

    IFS='|' read -r model_path gpu_layers ctx_size extra_args <<< "${MODELS[$model_name]}"

    # Check for saved optimized config and override defaults
    local is_optimized=""
    local saved_config
    if saved_config=$(get_saved_config "$model_name"); then
        read -r saved_gpu saved_ctx saved_batch <<< "$saved_config"
        if [[ -n "$saved_gpu" ]]; then
            gpu_layers="$saved_gpu"
            [[ -n "$saved_ctx" ]] && ctx_size="$saved_ctx"
            is_optimized="yes"
        fi
    fi

    if [[ ! -f "$model_path" ]]; then
        echo "ERROR: Model file not found: $model_path" >&2
        return 1
    fi

    setup_gpu_environment
    mkdir -p "$RUN_DIR"

    local pid_file=$(get_pid_file "$model_name")

    if [[ -n "$is_optimized" ]]; then
        echo "Starting $model_name in foreground mode (OPTIMIZED)"
        echo "Using optimized config from model-configs.json"
    else
        echo "Starting $model_name in foreground mode (default config)"
    fi
    echo "Model: $(basename "$model_path")"
    echo "GPU Layers: $gpu_layers, Context: $ctx_size, Port: $port"

    # Write PID file (current process, will be replaced by exec)
    echo $$ > "$pid_file"

    # Exec replaces this process with llama-server
    exec "$LLAMA_SERVER" \
        --model "$model_path" \
        --host "$DEFAULT_HOST" \
        --port "$port" \
        --n-gpu-layers "$gpu_layers" \
        --ctx-size "$ctx_size" \
        --threads "$DEFAULT_THREADS" \
        --batch-size "$DEFAULT_BATCH_SIZE" \
        --no-mmap \
        --alias "$model_name" \
        $extra_args
}

stop_model() {
    local model_name="$1"
    local pid_file=$(get_pid_file "$model_name")

    if [[ ! -f "$pid_file" ]]; then
        print_warning "Model '$model_name' is not running"
        return 0
    fi

    local pid=$(cat "$pid_file")

    if kill -0 "$pid" 2>/dev/null; then
        print_info "Stopping '$model_name' (PID: $pid)..."
        kill "$pid" 2>/dev/null

        # Wait for graceful shutdown
        local count=0
        while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
            sleep 1
            ((count++))
        done

        if kill -0 "$pid" 2>/dev/null; then
            print_warning "Force killing..."
            kill -9 "$pid" 2>/dev/null
        fi

        print_success "Stopped '$model_name'"
    fi

    rm -f "$pid_file"
}

stop_all() {
    print_header "Stopping All Servers"

    for model_name in "${!MODELS[@]}"; do
        if is_running "$model_name"; then
            stop_model "$model_name"
        fi
    done

    # Also kill any orphaned llama-server processes
    pkill -f "llama-server" 2>/dev/null || true

    print_success "All servers stopped"
}

show_status() {
    print_header "Server Status"

    printf "%-25s %-8s %-18s %-8s %s\n" "MODEL" "PORT" "STATUS" "PID" "MEMORY"
    printf "%-25s %-8s %-18s %-8s %s\n" "-----" "----" "------" "---" "------"

    local running_count=0

    for model_name in "${!MODELS[@]}"; do
        local pid_file=$(get_pid_file "$model_name")
        local status="${RED}stopped${NC}"
        local pid="-"
        local mem="-"
        local port="-"

        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file" 2>/dev/null) || pid=""
            if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
                # Check if model has optimized config
                local saved_config
                if saved_config=$(get_saved_config "$model_name") && [[ -n "$saved_config" ]]; then
                    status="${GREEN}running (opt)${NC}"
                else
                    status="${YELLOW}running${NC}"
                fi
                mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1fGB", $1/1024/1024}') || mem="-"
                # Try to get port from process cmdline
                port=$(ps -o args= -p "$pid" 2>/dev/null | grep -oE '\-\-port [0-9]+' | awk '{print $2}') || port=""
                [[ -z "$port" ]] && port="8081"
                running_count=$((running_count + 1))
            fi
        fi

        printf "%-25s %-8s " "$model_name" "$port"
        echo -en "$status"
        printf " %-8s %s\n" "$pid" "$mem"
    done

    echo ""
    if [[ $running_count -gt 0 ]]; then
        print_info "$running_count server(s) running"
        echo ""
        echo -e "Legend: ${GREEN}running (opt)${NC} = optimized config, ${YELLOW}running${NC} = default config"
    else
        print_info "No servers running"
    fi
}

list_models() {
    print_header "Available Models"

    printf "%-25s %-10s %-8s %-8s %s\n" "NAME" "GPU_LAYERS" "CTX" "SIZE" "OPTIMIZED"
    printf "%-25s %-10s %-8s %-8s %s\n" "----" "----------" "---" "----" "---------"

    for model_name in $(echo "${!MODELS[@]}" | tr ' ' '\n' | sort); do
        IFS='|' read -r model_path gpu_layers ctx_size extra_args <<< "${MODELS[$model_name]}"

        local size="-"
        if [[ -f "$model_path" ]]; then
            size=$(du -h "$model_path" 2>/dev/null | awk '{print $1}')
        fi

        # Check if model has saved optimized config
        local optimized=""
        local saved_config
        if saved_config=$(get_saved_config "$model_name"); then
            read -r saved_gpu saved_ctx saved_batch <<< "$saved_config"
            gpu_layers="$saved_gpu"  # Show saved GPU layers
            [[ -n "$saved_ctx" ]] && ctx_size="$saved_ctx"
            optimized="✓"
        fi

        printf "%-25s %-10s %-8s %-8s %s\n" "$model_name" "$gpu_layers" "$ctx_size" "$size" "$optimized"
    done

    echo ""
    echo "Usage: $0 <model_name> [port]"
    echo "Example: $0 qwen3-235b 8081"
    echo ""
    echo "Models marked with ✓ have optimized configs in model-configs.json"
}

show_logs() {
    local model_name="$1"
    local log_file=$(get_log_file "$model_name")

    if [[ -f "$log_file" ]]; then
        tail -f "$log_file"
    else
        print_error "No log file found for '$model_name'"
        return 1
    fi
}

show_help() {
    echo "LLM Server Startup Script for Strix Halo"
    echo ""
    echo "Usage: $0 <command|model_name> [options]"
    echo ""
    echo "Commands:"
    echo "  <model_name> [port]  Start a specific model (default port: 8081)"
    echo "  stop [model_name]    Stop all servers or a specific model"
    echo "  status               Show status of all servers"
    echo "  list                 List available models"
    echo "  logs <model_name>    Follow logs for a model"
    echo "  help                 Show this help"
    echo ""
    echo "Examples:"
    echo "  $0 qwen3-235b        Start Qwen3-235B on port 8081"
    echo "  $0 qwen2.5-7b 8082   Start Qwen2.5-7B on port 8082"
    echo "  $0 stop              Stop all servers"
    echo "  $0 status            Check what's running"
    echo ""
    echo "Environment Variables:"
    echo "  MODELS_DIR           Models directory (default: ./models)"
    echo "  LLAMA_SERVER         Path to llama-server binary"
}

#===============================================================================
# Main
#===============================================================================

main() {
    local command="${1:-help}"

    case "$command" in
        run)
            # Foreground mode for systemd
            if [[ -z "$2" ]]; then
                echo "ERROR: Please specify a model name" >&2
                exit 1
            fi
            run_model_foreground "$2" "${3:-$DEFAULT_PORT}"
            ;;
        stop)
            if [[ -n "$2" ]]; then
                stop_model "$2"
            else
                stop_all
            fi
            ;;
        status)
            show_status
            ;;
        list)
            list_models
            ;;
        logs)
            if [[ -z "$2" ]]; then
                print_error "Please specify a model name"
                exit 1
            fi
            show_logs "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # Assume it's a model name
            if [[ -n "${MODELS[$command]}" ]]; then
                start_model "$command" "${2:-$DEFAULT_PORT}"
            else
                print_error "Unknown command or model: $command"
                echo ""
                show_help
                exit 1
            fi
            ;;
    esac
}

main "$@"
