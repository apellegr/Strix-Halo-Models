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
#   ./start-llm-server.sh qwen3-235b -c 16384  # Start with custom context size
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

# Source environment file if it exists
[[ -f "$SCRIPT_DIR/.env" ]] && source "$SCRIPT_DIR/.env"

# Ensure MODELS_DIR is an absolute path
MODELS_DIR="${MODELS_DIR:-$SCRIPT_DIR/models}"
[[ "$MODELS_DIR" != /* ]] && MODELS_DIR="$SCRIPT_DIR/$MODELS_DIR"
MODELS_DIR="$(cd "$MODELS_DIR" 2>/dev/null && pwd)" || MODELS_DIR="$SCRIPT_DIR/models"
RUN_DIR="${RUN_DIR:-$HOME/.llm-servers}"
LLAMA_SERVER="${LLAMA_SERVER:-$HOME/.local/bin/llama-server}"
CONFIG_FILE="${CONFIG_FILE:-$SCRIPT_DIR/model-configs.json}"

# Default server settings
DEFAULT_HOST="0.0.0.0"
DEFAULT_PORT="8081"
DEFAULT_THREADS="16"          # Physical cores (SMT2 system)
DEFAULT_BATCH_SIZE="1024"     # Larger batch for faster prompt processing
DEFAULT_CTX_SIZE="4096"
DEFAULT_PARALLEL="1"          # Number of parallel slots (reduce for faster individual requests)
# DEFAULT_FLASH_ATTN="on"     # Disabled - may cause high CPU when idle on Strix Halo

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
# Model Discovery
# Dynamically finds models in the models/ directory
# Format: model_path|gpu_layers|ctx_size|extra_args
#===============================================================================

declare -A MODELS

# Get default GPU layers based on model file size
get_default_gpu_layers() {
    local model_path="$1"
    local size_gb=0

    # Calculate total size for multi-part models
    local base_path="${model_path%-00001-of-*.gguf}"
    if [[ "$base_path" != "$model_path" ]]; then
        # Multi-part model - sum all parts
        size_gb=$(du -BG "${base_path}"*.gguf 2>/dev/null | awk '{sum+=$1} END {print sum}' | tr -d 'G')
    else
        size_gb=$(du -BG "$model_path" 2>/dev/null | awk '{print $1}' | tr -d 'G')
    fi

    # Determine GPU layers based on size
    # >80GB: 50 layers (very large, needs hybrid)
    # 40-80GB: 60 layers (large, hybrid mode)
    # <40GB: 999 (full GPU offload)
    if [[ "$size_gb" -gt 80 ]]; then
        echo "50"
    elif [[ "$size_gb" -gt 40 ]]; then
        echo "60"
    else
        echo "999"
    fi
}

# Get default context size based on model size
get_default_ctx_size() {
    local model_path="$1"
    local size_gb=$(du -BG "$model_path" 2>/dev/null | awk '{print $1}' | tr -d 'G')

    # Larger models get smaller context to save memory
    # >50GB: 4096
    # 20-50GB: 8192
    # 10-20GB: 16384
    # <10GB: 32768
    if [[ "$size_gb" -gt 50 ]]; then
        echo "4096"
    elif [[ "$size_gb" -gt 20 ]]; then
        echo "8192"
    elif [[ "$size_gb" -gt 10 ]]; then
        echo "16384"
    else
        echo "32768"
    fi
}

# Discover all models in the models directory
discover_models() {
    [[ ! -d "$MODELS_DIR" ]] && return

    # Find all .gguf files, excluding mmproj files (vision adapters)
    while IFS= read -r gguf_file; do
        # Skip mmproj files (vision model projectors)
        [[ "$gguf_file" == *"mmproj"* ]] && continue

        # Get the model directory path relative to MODELS_DIR
        local rel_path="${gguf_file#$MODELS_DIR/}"
        local category=$(echo "$rel_path" | cut -d'/' -f1)
        local model_name=$(echo "$rel_path" | cut -d'/' -f2)

        # Skip if we already have this model (handles multi-part models)
        [[ -n "${MODELS[$model_name]}" ]] && continue

        # For multi-part models, only use the first part
        if [[ "$gguf_file" == *"-of-"* ]]; then
            # Skip if not the first part
            [[ "$gguf_file" != *"-00001-of-"* ]] && continue
        fi

        # Get default settings based on model size
        local gpu_layers=$(get_default_gpu_layers "$gguf_file")
        local ctx_size=$(get_default_ctx_size "$gguf_file")

        # Register the model
        MODELS["$model_name"]="$gguf_file|$gpu_layers|$ctx_size|"

    done < <(find "$MODELS_DIR" -name "*.gguf" -type f 2>/dev/null | sort)
}

# Initialize models
discover_models

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
get_port_file() { echo "$RUN_DIR/${1}.port"; }
get_ctx_file() { echo "$RUN_DIR/${1}.ctx"; }

# Check if a port is available
is_port_available() {
    local port="$1"
    ! ss -tuln 2>/dev/null | grep -q ":${port} " && return 0
    return 1
}

# Find the next available port starting from a base port
find_available_port() {
    local base_port="${1:-$DEFAULT_PORT}"
    local max_port=$((base_port + 100))
    local port=$base_port

    while [[ $port -lt $max_port ]]; do
        if is_port_available "$port"; then
            echo "$port"
            return 0
        fi
        port=$((port + 1))
    done

    # Fallback to base port if all checked ports are in use
    echo "$base_port"
    return 1
}

# Get the port for a running model
get_model_port() {
    local model_name="$1"
    local port_file=$(get_port_file "$model_name")

    if [[ -f "$port_file" ]]; then
        cat "$port_file"
    else
        echo ""
    fi
}

#===============================================================================
# Memory Management
#===============================================================================

# Total system memory in GB
TOTAL_MEMORY_GB=$(awk '/MemTotal/ {printf "%.0f", $2/1024/1024}' /proc/meminfo)

# Get memory used by all running llama-server processes (in GB)
get_used_llm_memory() {
    local total_rss=0
    while read -r rss; do
        total_rss=$((total_rss + rss))
    done < <(pgrep -f "llama-server" | xargs -I{} ps -o rss= -p {} 2>/dev/null)
    echo $((total_rss / 1024 / 1024))
}

# Estimate memory needed for a model (in GB)
# Based on model file size + context overhead + compute buffers
# Conservative estimates for unified memory APU (Strix Halo)
estimate_model_memory() {
    local model_path="$1"
    local ctx_size="${2:-4096}"
    local model_size_gb=0

    # Calculate total size for multi-part models
    local base_path="${model_path%-00001-of-*.gguf}"
    if [[ "$base_path" != "$model_path" ]]; then
        model_size_gb=$(du -BG "${base_path}"*.gguf 2>/dev/null | awk '{sum+=$1} END {print sum}' | tr -d 'G')
    else
        model_size_gb=$(du -BG "$model_path" 2>/dev/null | awk '{print $1}' | tr -d 'G')
    fi

    # Estimate KV cache overhead based on context size and model size
    # Large context = large KV cache, especially for bigger models
    local ctx_overhead_gb=0
    if [[ "$ctx_size" -gt 16384 ]]; then
        # Large context: ~2-4GB per 8K context
        ctx_overhead_gb=$((ctx_size * 4 / 8192))
    elif [[ "$ctx_size" -gt 8192 ]]; then
        ctx_overhead_gb=$((ctx_size * 2 / 8192))
    else
        ctx_overhead_gb=$((ctx_size / 4096))
    fi

    # Add compute buffer overhead (significant for GPU offload)
    # Roughly 1GB per 10GB of model for compute graphs
    local compute_overhead=$((model_size_gb / 10 + 2))

    # Total with 20% safety margin for memory fragmentation
    local total=$((model_size_gb + ctx_overhead_gb + compute_overhead))
    total=$((total * 120 / 100))

    echo "$total"
}

# Check if there's enough memory to load a model
check_memory_available() {
    local model_path="$1"
    local ctx_size="$2"
    local model_name="$3"

    local used_gb=$(get_used_llm_memory)
    local needed_gb=$(estimate_model_memory "$model_path" "$ctx_size")
    local available_gb=$((TOTAL_MEMORY_GB - used_gb))

    # Leave 10GB buffer for system
    local safe_available=$((available_gb - 10))

    # Check for concurrent GPU-heavy models (unified memory limitation)
    if [[ $used_gb -gt 10 ]]; then
        # Another model is using significant memory
        local running_models=$(pgrep -c -f "llama-server" 2>/dev/null || echo 0)
        if [[ $running_models -gt 0 ]]; then
            echo ""
            print_warning "Concurrent Model Warning"
            echo "  Another model is already running using ~${used_gb}GB"
            echo "  Running multiple GPU-accelerated models simultaneously"
            echo "  may cause memory allocation failures on unified memory APUs."
            echo ""
            echo "  If this model fails to load, try:"
            echo "    - Stop other models first: ./start-llm-server.sh stop"
            echo "    - Use smaller context: reduces KV cache memory"
            echo "    - Use fewer GPU layers: offload to CPU instead"
            echo ""
        fi
    fi

    if [[ $needed_gb -gt $safe_available ]]; then
        echo ""
        print_warning "Memory Warning for $model_name"
        echo "  Estimated memory needed: ~${needed_gb}GB"
        echo "  Currently used by LLMs:  ~${used_gb}GB"
        echo "  Available (with buffer): ~${safe_available}GB"
        echo "  Total system memory:     ${TOTAL_MEMORY_GB}GB"
        echo ""

        if [[ $needed_gb -gt $available_gb ]]; then
            print_error "Likely insufficient memory! Model may fail to load."
            echo "  Consider: stopping other models, reducing context, or using fewer GPU layers"
            echo ""
            return 1
        else
            print_warning "Memory is tight. Model may load slowly or fail."
            echo ""
        fi
    fi

    return 0
}

# Get saved optimized config from model-configs.json
# Returns: gpu_layers ctx_size batch_size n_predict (space separated)
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
    local saved_n_predict=$(jq -r ".models[\"$model_name\"].n_predict // empty" "$CONFIG_FILE")

    if [[ -n "$saved_gpu_layers" ]]; then
        echo "$saved_gpu_layers $saved_ctx_size $saved_batch_size $saved_n_predict"
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
    local requested_port="$2"
    local custom_ctx="$3"

    if [[ -z "${MODELS[$model_name]}" ]]; then
        print_error "Unknown model: $model_name"
        echo "Use './start-llm-server.sh list' to see available models"
        return 1
    fi

    if is_running "$model_name"; then
        local existing_port=$(get_model_port "$model_name")
        print_warning "Model '$model_name' is already running on port $existing_port"
        return 0
    fi

    # Parse model config
    IFS='|' read -r model_path gpu_layers ctx_size extra_args <<< "${MODELS[$model_name]}"

    # Check for saved optimized config and override defaults
    local is_optimized=""
    local saved_config
    local n_predict=""
    if saved_config=$(get_saved_config "$model_name"); then
        read -r saved_gpu saved_ctx saved_batch saved_n_predict <<< "$saved_config"
        if [[ -n "$saved_gpu" ]]; then
            gpu_layers="$saved_gpu"
            [[ -n "$saved_ctx" ]] && ctx_size="$saved_ctx"
            [[ -n "$saved_n_predict" ]] && n_predict="$saved_n_predict"
            is_optimized="yes"
        fi
    fi

    # Override context size if user specified one
    local user_ctx=""
    if [[ -n "$custom_ctx" ]]; then
        ctx_size="$custom_ctx"
        user_ctx="$custom_ctx"
    fi

    if [[ ! -f "$model_path" ]]; then
        print_error "Model file not found: $model_path"
        return 1
    fi

    # Check memory availability
    check_memory_available "$model_path" "$ctx_size" "$model_name"

    # Setup environment
    setup_gpu_environment

    # Create run directory
    mkdir -p "$RUN_DIR"

    # Determine port - use requested port or find an available one
    local port
    if [[ -n "$requested_port" ]]; then
        port="$requested_port"
        if ! is_port_available "$port"; then
            print_warning "Port $port is in use, finding available port..."
            port=$(find_available_port "$DEFAULT_PORT")
        fi
    else
        port=$(find_available_port "$DEFAULT_PORT")
    fi

    local pid_file=$(get_pid_file "$model_name")
    local log_file=$(get_log_file "$model_name")
    local port_file=$(get_port_file "$model_name")

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

    # Save the port for status tracking
    echo "$port" > "$port_file"

    # Save custom context size if user specified one
    local ctx_file=$(get_ctx_file "$model_name")
    if [[ -n "$user_ctx" ]]; then
        echo "$user_ctx" > "$ctx_file"
    else
        rm -f "$ctx_file"
    fi

    # Use batch size from config if available
    local batch_size="${saved_batch:-$DEFAULT_BATCH_SIZE}"

    # Start the server
    # Build optional args
    local n_predict_arg=""
    [[ -n "$n_predict" ]] && n_predict_arg="--n-predict $n_predict"

    nohup "$LLAMA_SERVER" \
        --model "$model_path" \
        --host "$DEFAULT_HOST" \
        --port "$port" \
        --n-gpu-layers "$gpu_layers" \
        --ctx-size "$ctx_size" \
        --threads "$DEFAULT_THREADS" \
        --batch-size "$batch_size" \
        --parallel "$DEFAULT_PARALLEL" \
        --no-mmap \
        --metrics \
        --alias "$model_name" \
        $n_predict_arg \
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
    local requested_port="$2"
    local custom_ctx="$3"

    if [[ -z "${MODELS[$model_name]}" ]]; then
        echo "ERROR: Unknown model: $model_name" >&2
        return 1
    fi

    IFS='|' read -r model_path gpu_layers ctx_size extra_args <<< "${MODELS[$model_name]}"

    # Check for saved optimized config and override defaults
    local is_optimized=""
    local saved_config
    local n_predict=""
    if saved_config=$(get_saved_config "$model_name"); then
        read -r saved_gpu saved_ctx saved_batch saved_n_predict <<< "$saved_config"
        if [[ -n "$saved_gpu" ]]; then
            gpu_layers="$saved_gpu"
            [[ -n "$saved_ctx" ]] && ctx_size="$saved_ctx"
            [[ -n "$saved_n_predict" ]] && n_predict="$saved_n_predict"
            is_optimized="yes"
        fi
    fi

    # Override context size if user specified one
    local user_ctx=""
    if [[ -n "$custom_ctx" ]]; then
        ctx_size="$custom_ctx"
        user_ctx="$custom_ctx"
    fi

    if [[ ! -f "$model_path" ]]; then
        echo "ERROR: Model file not found: $model_path" >&2
        return 1
    fi

    # Check memory availability (warning only for foreground mode)
    check_memory_available "$model_path" "$ctx_size" "$model_name" || true

    setup_gpu_environment
    mkdir -p "$RUN_DIR"

    # Determine port - use requested port or find an available one
    local port
    if [[ -n "$requested_port" ]]; then
        port="$requested_port"
        if ! is_port_available "$port"; then
            echo "Port $port is in use, finding available port..."
            port=$(find_available_port "$DEFAULT_PORT")
        fi
    else
        port=$(find_available_port "$DEFAULT_PORT")
    fi

    local pid_file=$(get_pid_file "$model_name")
    local port_file=$(get_port_file "$model_name")

    if [[ -n "$is_optimized" ]]; then
        echo "Starting $model_name in foreground mode (OPTIMIZED)"
        echo "Using optimized config from model-configs.json"
    else
        echo "Starting $model_name in foreground mode (default config)"
    fi
    echo "Model: $(basename "$model_path")"
    echo "GPU Layers: $gpu_layers, Context: $ctx_size, Port: $port"

    # Write PID and port files
    echo $$ > "$pid_file"
    echo "$port" > "$port_file"

    # Save custom context size if user specified one
    local ctx_file=$(get_ctx_file "$model_name")
    if [[ -n "$user_ctx" ]]; then
        echo "$user_ctx" > "$ctx_file"
    else
        rm -f "$ctx_file"
    fi

    # Use batch size from config if available
    local batch_size="${saved_batch:-$DEFAULT_BATCH_SIZE}"

    # Exec replaces this process with llama-server
    # Build optional args
    local n_predict_arg=""
    [[ -n "$n_predict" ]] && n_predict_arg="--n-predict $n_predict"

    exec "$LLAMA_SERVER" \
        --model "$model_path" \
        --host "$DEFAULT_HOST" \
        --port "$port" \
        --n-gpu-layers "$gpu_layers" \
        --ctx-size "$ctx_size" \
        --threads "$DEFAULT_THREADS" \
        --batch-size "$batch_size" \
        --parallel "$DEFAULT_PARALLEL" \
        --no-mmap \
        --metrics \
        --alias "$model_name" \
        $n_predict_arg \
        $extra_args
}

stop_model() {
    local model_name="$1"
    local pid_file=$(get_pid_file "$model_name")
    local port_file=$(get_port_file "$model_name")
    local ctx_file=$(get_ctx_file "$model_name")

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

    rm -f "$pid_file" "$port_file" "$ctx_file"
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

    printf "%-25s %-8s %-18s %-8s %-8s %s\n" "MODEL" "PORT" "STATUS" "PID" "CTX" "MEMORY"
    printf "%-25s %-8s %-18s %-8s %-8s %s\n" "-----" "----" "------" "---" "---" "------"

    local running_count=0

    for model_name in "${!MODELS[@]}"; do
        local pid_file=$(get_pid_file "$model_name")
        local port_file=$(get_port_file "$model_name")
        local ctx_file=$(get_ctx_file "$model_name")
        local status="${RED}stopped${NC}"
        local pid="-"
        local mem="-"
        local port="-"
        local ctx="-"

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
                # Get port from port file
                port=$(cat "$port_file" 2>/dev/null) || port="-"
                # Get custom context size if user specified one
                if [[ -f "$ctx_file" ]]; then
                    ctx=$(cat "$ctx_file" 2>/dev/null) || ctx="-"
                fi
                running_count=$((running_count + 1))
            fi
        fi

        printf "%-25s %-8s " "$model_name" "$port"
        echo -en "$status"
        printf " %-8s %-8s %s\n" "$pid" "$ctx" "$mem"
    done

    echo ""
    if [[ $running_count -gt 0 ]]; then
        print_info "$running_count server(s) running"
        echo ""
        echo -e "Legend: ${GREEN}running (opt)${NC} = optimized config, ${YELLOW}running${NC} = default config"
        echo "        CTX = user-specified context size (- means using default/optimized)"
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
    echo "Options:"
    echo "  -c, --ctx <size>     Set custom context window size (e.g., 8192, 16384, 32768)"
    echo "  -p, --port <port>    Set server port (alternative to positional port)"
    echo ""
    echo "Examples:"
    echo "  $0 qwen3-235b                    Start Qwen3-235B on port 8081"
    echo "  $0 qwen2.5-7b 8082               Start Qwen2.5-7B on port 8082"
    echo "  $0 qwen3-235b -c 16384           Start with 16K context window"
    echo "  $0 qwen3-235b -c 32768 -p 8082   Start with 32K context on port 8082"
    echo "  $0 stop                          Stop all servers"
    echo "  $0 status                        Check what's running"
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
    local port=""
    local ctx=""
    local model_name=""

    # Parse arguments
    shift || true
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -c|--ctx)
                ctx="$2"
                shift 2
                ;;
            -p|--port)
                port="$2"
                shift 2
                ;;
            *)
                # First positional arg after command
                if [[ -z "$port" && "$1" =~ ^[0-9]+$ && "$1" -gt 1024 ]]; then
                    port="$1"
                else
                    model_name="$1"
                fi
                shift
                ;;
        esac
    done

    case "$command" in
        run)
            # Foreground mode for systemd
            if [[ -z "$model_name" ]]; then
                echo "ERROR: Please specify a model name" >&2
                exit 1
            fi
            run_model_foreground "$model_name" "${port:-$DEFAULT_PORT}" "$ctx"
            ;;
        stop)
            if [[ -n "$model_name" ]]; then
                stop_model "$model_name"
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
            if [[ -z "$model_name" ]]; then
                print_error "Please specify a model name"
                exit 1
            fi
            show_logs "$model_name"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            # Assume command is actually the model name
            model_name="$command"
            if [[ -n "${MODELS[$model_name]}" ]]; then
                start_model "$model_name" "${port:-$DEFAULT_PORT}" "$ctx"
            else
                print_error "Unknown command or model: $model_name"
                echo ""
                show_help
                exit 1
            fi
            ;;
    esac
}

main "$@"
