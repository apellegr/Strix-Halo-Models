#!/bin/bash

#===============================================================================
# Multi-Model LLM Server Manager for Strix Halo
#===============================================================================
# Manages multiple llama-server instances running different models on
# different ports. Optimized for AMD Ryzen AI Max+ 395 with 128GB RAM.
#
# Usage:
#   ./llm-server-manager.sh start          # Start all configured models
#   ./llm-server-manager.sh stop           # Stop all running servers
#   ./llm-server-manager.sh status         # Show status of all servers
#   ./llm-server-manager.sh list           # List available models
#   ./llm-server-manager.sh start <name>   # Start a specific model
#   ./llm-server-manager.sh stop <name>    # Stop a specific model
#   ./llm-server-manager.sh logs <name>    # View logs for a model
#===============================================================================

set -e

#===============================================================================
# Configuration
#===============================================================================

# Path to llama-server binary
LLAMA_SERVER="${LLAMA_SERVER:-llama-server}"

# Base directory for models
MODELS_DIR="${MODELS_DIR:-$HOME/llm-models}"

# Directory for logs and PID files
RUN_DIR="${RUN_DIR:-$HOME/.llm-servers}"

# Starting port (each model gets the next available port)
BASE_PORT="${BASE_PORT:-8080}"

# Host to bind to (0.0.0.0 for all interfaces)
HOST="${HOST:-0.0.0.0}"

# Default settings optimized for Strix Halo
DEFAULT_GPU_LAYERS=999        # Offload all layers to GPU
DEFAULT_CONTEXT_SIZE=8192     # Good balance for most models
DEFAULT_THREADS=$(nproc)      # Use all CPU threads
DEFAULT_BATCH_SIZE=512        # Batch size for prompt processing

#===============================================================================
# Model Configuration
# Format: "name|path|port|context_size|extra_args"
# Leave context_size empty for default, extra_args for additional options
#===============================================================================

declare -A MODEL_CONFIG

# Auto-discover models and assign ports
discover_models() {
    local port=$BASE_PORT
    
    # Find all .gguf files in the models directory
    while IFS= read -r -d '' model_file; do
        local model_name=$(basename "$(dirname "$model_file")")
        local category=$(basename "$(dirname "$(dirname "$model_file")")")
        local display_name="${category}/${model_name}"
        
        # Skip if already configured
        if [[ -z "${MODEL_CONFIG[$display_name]}" ]]; then
            MODEL_CONFIG["$display_name"]="$model_file|$port|$DEFAULT_CONTEXT_SIZE|"
            ((port++))
        fi
    done < <(find "$MODELS_DIR" -name "*.gguf" -type f -print0 2>/dev/null | head -z -n 50)
}

# You can also manually configure specific models with custom settings:
# Uncomment and modify as needed:
#
# MODEL_CONFIG["qwen-7b"]="$MODELS_DIR/fast/qwen2.5-7b/Qwen2.5-7B-Instruct-Q5_K_M.gguf|8080|8192|"
# MODEL_CONFIG["qwen-32b"]="$MODELS_DIR/balanced/qwen2.5-32b/Qwen2.5-32B-Instruct-Q4_K_M.gguf|8081|4096|"
# MODEL_CONFIG["llama-70b"]="$MODELS_DIR/large/llama-3.3-70b/Llama-3.3-70B-Instruct-Q4_K_M.gguf|8082|4096|"
# MODEL_CONFIG["deepseek-r1"]="$MODELS_DIR/balanced/deepseek-r1-32b/DeepSeek-R1-Distill-Qwen-32B-Q4_K_M.gguf|8083|8192|"
# MODEL_CONFIG["coder-32b"]="$MODELS_DIR/coding/qwen2.5-coder-32b/Qwen2.5-Coder-32B-Instruct-Q4_K_M.gguf|8084|16384|"

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
    echo -e "\n${CYAN}╔════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC} $1"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════╝${NC}\n"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

get_pid_file() {
    local name=$1
    echo "$RUN_DIR/${name//\//_}.pid"
}

get_log_file() {
    local name=$1
    echo "$RUN_DIR/${name//\//_}.log"
}

is_running() {
    local name=$1
    local pid_file=$(get_pid_file "$name")
    
    if [[ -f "$pid_file" ]]; then
        local pid=$(cat "$pid_file")
        if kill -0 "$pid" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

get_model_info() {
    local name=$1
    local config="${MODEL_CONFIG[$name]}"
    
    IFS='|' read -r path port context extra <<< "$config"
    
    echo "$path|$port|${context:-$DEFAULT_CONTEXT_SIZE}|$extra"
}

#===============================================================================
# Server Management
#===============================================================================

start_model() {
    local name=$1
    local config="${MODEL_CONFIG[$name]}"
    
    if [[ -z "$config" ]]; then
        print_error "Model '$name' not found in configuration"
        return 1
    fi
    
    if is_running "$name"; then
        print_warning "Model '$name' is already running"
        return 0
    fi
    
    IFS='|' read -r model_path port context extra <<< "$config"
    context=${context:-$DEFAULT_CONTEXT_SIZE}
    
    if [[ ! -f "$model_path" ]]; then
        print_error "Model file not found: $model_path"
        return 1
    fi
    
    local pid_file=$(get_pid_file "$name")
    local log_file=$(get_log_file "$name")
    
    print_info "Starting '$name' on port $port..."
    print_info "  Model: $(basename "$model_path")"
    print_info "  Context: $context tokens"
    
    # Build the command
    local cmd="$LLAMA_SERVER \
        --model \"$model_path\" \
        --host $HOST \
        --port $port \
        --n-gpu-layers $DEFAULT_GPU_LAYERS \
        --ctx-size $context \
        --threads $DEFAULT_THREADS \
        --batch-size $DEFAULT_BATCH_SIZE \
        --flash-attn \
        $extra"
    
    # Start the server in background
    eval "nohup $cmd > \"$log_file\" 2>&1 &"
    local pid=$!
    
    echo "$pid" > "$pid_file"
    
    # Wait a moment and check if it started
    sleep 2
    
    if kill -0 "$pid" 2>/dev/null; then
        print_success "Started '$name' (PID: $pid, Port: $port)"
        return 0
    else
        print_error "Failed to start '$name'. Check log: $log_file"
        rm -f "$pid_file"
        return 1
    fi
}

stop_model() {
    local name=$1
    local pid_file=$(get_pid_file "$name")
    
    if [[ ! -f "$pid_file" ]]; then
        print_warning "Model '$name' is not running (no PID file)"
        return 0
    fi
    
    local pid=$(cat "$pid_file")
    
    if kill -0 "$pid" 2>/dev/null; then
        print_info "Stopping '$name' (PID: $pid)..."
        kill "$pid" 2>/dev/null
        
        # Wait for graceful shutdown
        local count=0
        while kill -0 "$pid" 2>/dev/null && [[ $count -lt 10 ]]; do
            sleep 1
            ((count++))
        done
        
        # Force kill if still running
        if kill -0 "$pid" 2>/dev/null; then
            print_warning "Force killing '$name'..."
            kill -9 "$pid" 2>/dev/null
        fi
        
        print_success "Stopped '$name'"
    else
        print_warning "Model '$name' was not running"
    fi
    
    rm -f "$pid_file"
}

start_all() {
    print_header "Starting All Models"
    
    mkdir -p "$RUN_DIR"
    
    local started=0
    local failed=0
    
    for name in "${!MODEL_CONFIG[@]}"; do
        if start_model "$name"; then
            ((started++))
        else
            ((failed++))
        fi
        echo ""
    done
    
    echo -e "\n${GREEN}Started: $started${NC} | ${RED}Failed: $failed${NC}"
}

stop_all() {
    print_header "Stopping All Models"
    
    for name in "${!MODEL_CONFIG[@]}"; do
        stop_model "$name"
    done
    
    print_success "All servers stopped"
}

show_status() {
    print_header "Server Status"
    
    printf "%-30s %-8s %-10s %-8s %s\n" "MODEL" "PORT" "STATUS" "PID" "MEMORY"
    printf "%-30s %-8s %-10s %-8s %s\n" "-----" "----" "------" "---" "------"
    
    for name in "${!MODEL_CONFIG[@]}"; do
        IFS='|' read -r model_path port context extra <<< "${MODEL_CONFIG[$name]}"
        
        local status="${RED}stopped${NC}"
        local pid="-"
        local mem="-"
        
        local pid_file=$(get_pid_file "$name")
        if [[ -f "$pid_file" ]]; then
            pid=$(cat "$pid_file")
            if kill -0 "$pid" 2>/dev/null; then
                status="${GREEN}running${NC}"
                # Get memory usage
                mem=$(ps -o rss= -p "$pid" 2>/dev/null | awk '{printf "%.1fGB", $1/1024/1024}')
            fi
        fi
        
        printf "%-30s %-8s " "$name" "$port"
        echo -en "$status"
        printf " %-8s %s\n" "$pid" "$mem"
    done
    
    echo ""
    echo -e "${BLUE}API Endpoints:${NC}"
    for name in "${!MODEL_CONFIG[@]}"; do
        IFS='|' read -r model_path port context extra <<< "${MODEL_CONFIG[$name]}"
        if is_running "$name"; then
            echo "  $name: http://$HOST:$port/v1"
        fi
    done
}

list_models() {
    print_header "Available Models"
    
    printf "%-30s %-8s %-10s %s\n" "NAME" "PORT" "CONTEXT" "MODEL FILE"
    printf "%-30s %-8s %-10s %s\n" "----" "----" "-------" "----------"
    
    for name in "${!MODEL_CONFIG[@]}"; do
        IFS='|' read -r model_path port context extra <<< "${MODEL_CONFIG[$name]}"
        context=${context:-$DEFAULT_CONTEXT_SIZE}
        printf "%-30s %-8s %-10s %s\n" "$name" "$port" "$context" "$(basename "$model_path")"
    done
}

show_logs() {
    local name=$1
    local log_file=$(get_log_file "$name")
    
    if [[ -f "$log_file" ]]; then
        tail -f "$log_file"
    else
        print_error "No log file found for '$name'"
        return 1
    fi
}

show_openwebui_config() {
    print_header "Open WebUI Configuration"
    
    echo "Add these endpoints to Open WebUI (Settings → Connections → OpenAI API):"
    echo ""
    
    local running=0
    for name in "${!MODEL_CONFIG[@]}"; do
        if is_running "$name"; then
            IFS='|' read -r model_path port context extra <<< "${MODEL_CONFIG[$name]}"
            echo -e "  ${GREEN}$name${NC}"
            echo "    URL: http://localhost:$port/v1"
            echo "    Key: not-needed"
            echo ""
            ((running++))
        fi
    done
    
    if [[ $running -eq 0 ]]; then
        print_warning "No servers are currently running. Start some first!"
    else
        echo "For Docker-based Open WebUI, use 'host.docker.internal' instead of 'localhost'"
    fi
}

show_help() {
    echo "LLM Server Manager for Strix Halo"
    echo ""
    echo "Usage: $0 <command> [model_name]"
    echo ""
    echo "Commands:"
    echo "  start [name]     Start all models, or a specific model"
    echo "  stop [name]      Stop all models, or a specific model"
    echo "  restart [name]   Restart all models, or a specific model"
    echo "  status           Show status of all servers"
    echo "  list             List available models"
    echo "  logs <name>      Follow logs for a specific model"
    echo "  openwebui        Show Open WebUI connection info"
    echo "  help             Show this help message"
    echo ""
    echo "Environment Variables:"
    echo "  MODELS_DIR       Models directory (default: ~/llm-models)"
    echo "  LLAMA_SERVER     Path to llama-server binary (default: llama-server)"
    echo "  BASE_PORT        Starting port number (default: 8080)"
    echo "  HOST             Host to bind to (default: 0.0.0.0)"
    echo ""
    echo "Examples:"
    echo "  $0 start                    # Start all discovered models"
    echo "  $0 start fast/qwen2.5-7b    # Start a specific model"
    echo "  $0 status                   # Check what's running"
    echo "  $0 logs fast/qwen2.5-7b     # View logs for a model"
    echo "  $0 openwebui                # Get Open WebUI config"
}

#===============================================================================
# Main
#===============================================================================

main() {
    # Create run directory
    mkdir -p "$RUN_DIR"
    
    # Check for llama-server
    if ! command -v "$LLAMA_SERVER" &> /dev/null; then
        print_error "llama-server not found. Set LLAMA_SERVER env var or add to PATH."
        echo "  Install: https://github.com/ggerganov/llama.cpp"
        exit 1
    fi
    
    # Auto-discover models
    discover_models
    
    if [[ ${#MODEL_CONFIG[@]} -eq 0 ]]; then
        print_error "No models found in $MODELS_DIR"
        echo "  Download models first with the download script."
        exit 1
    fi
    
    local command=${1:-help}
    local model_name=$2
    
    case $command in
        start)
            if [[ -n "$model_name" ]]; then
                start_model "$model_name"
            else
                start_all
            fi
            ;;
        stop)
            if [[ -n "$model_name" ]]; then
                stop_model "$model_name"
            else
                stop_all
            fi
            ;;
        restart)
            if [[ -n "$model_name" ]]; then
                stop_model "$model_name"
                sleep 2
                start_model "$model_name"
            else
                stop_all
                sleep 2
                start_all
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
        openwebui|webui)
            show_openwebui_config
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
