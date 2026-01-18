#!/bin/bash

#===============================================================================
# Start LLM Server with Rate Limiting
#===============================================================================
# Starts the llama-server with high-performance batch_size=1024 and a rate
# limiting proxy to prevent GPU MES scheduler crashes.
#
# Architecture:
#   Client -> Rate Limiter (port 8080) -> llama-server (port 8081)
#
# Usage:
#   ./start-llm-with-rate-limit.sh [model_name]    # Start with rate limiting
#   ./start-llm-with-rate-limit.sh stop            # Stop everything
#   ./start-llm-with-rate-limit.sh status          # Check status
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Configuration
MODEL_NAME="${1:-qwen3-235b-thinking}"
BACKEND_PORT=8081
PROXY_PORT=8080
MAX_CONCURRENT=5  # Safe limit to prevent MES crashes
RATE_LIMITER_PID_FILE="$HOME/.llm-servers/rate-limiter.pid"
RATE_LIMITER_LOG="$HOME/.llm-servers/rate-limiter.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

log_info()  { echo -e "${BLUE}[INFO]${NC} $1"; }
log_ok()    { echo -e "${GREEN}[OK]${NC} $1"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n"
}

start_server() {
    local model="$1"

    print_header "Starting LLM Server with Rate Limiting"

    log_info "Model: $model"
    log_info "Backend port: $BACKEND_PORT"
    log_info "Proxy port: $PROXY_PORT (use this for API calls)"
    log_info "Max concurrent: $MAX_CONCURRENT"
    echo ""

    # Check current batch_size
    local batch_size=$(jq -r ".models[\"$model\"].batch_size // 1024" model-configs.json)
    log_info "Batch size: $batch_size"

    # Start the llama-server
    log_info "Starting llama-server on port $BACKEND_PORT..."
    ./start-llm-server.sh "$model" "$BACKEND_PORT"

    # Wait for server to be ready
    log_info "Waiting for llama-server to be ready..."
    local timeout=300
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s "http://localhost:$BACKEND_PORT/health" 2>/dev/null | grep -q '"status":"ok"'; then
            log_ok "llama-server is ready"
            break
        fi
        sleep 5
        elapsed=$((elapsed + 5))
    done

    if [[ $elapsed -ge $timeout ]]; then
        log_error "llama-server failed to start"
        return 1
    fi

    # Start the rate limiter
    log_info "Starting rate limiter proxy on port $PROXY_PORT..."
    mkdir -p "$(dirname "$RATE_LIMITER_PID_FILE")"

    nohup python3 ./llm-rate-limiter.py \
        --port "$PROXY_PORT" \
        --backend "http://localhost:$BACKEND_PORT" \
        --max-concurrent "$MAX_CONCURRENT" \
        > "$RATE_LIMITER_LOG" 2>&1 &

    echo $! > "$RATE_LIMITER_PID_FILE"

    sleep 2

    if kill -0 "$(cat "$RATE_LIMITER_PID_FILE")" 2>/dev/null; then
        log_ok "Rate limiter started (PID: $(cat "$RATE_LIMITER_PID_FILE"))"
    else
        log_error "Rate limiter failed to start"
        cat "$RATE_LIMITER_LOG"
        return 1
    fi

    # Final status
    echo ""
    print_header "Server Ready"
    echo -e "  ${GREEN}API Endpoint:${NC} http://localhost:$PROXY_PORT/v1"
    echo -e "  ${GREEN}Health Check:${NC} http://localhost:$PROXY_PORT/health"
    echo -e "  ${GREEN}Proxy Stats:${NC}  http://localhost:$PROXY_PORT/proxy/stats"
    echo ""
    echo -e "  ${YELLOW}Note:${NC} Use port $PROXY_PORT for all API calls (rate limited)"
    echo -e "        Port $BACKEND_PORT is the direct backend (not rate limited)"
    echo ""
}

stop_server() {
    print_header "Stopping LLM Server and Rate Limiter"

    # Stop rate limiter
    if [[ -f "$RATE_LIMITER_PID_FILE" ]]; then
        local pid=$(cat "$RATE_LIMITER_PID_FILE")
        if kill -0 "$pid" 2>/dev/null; then
            log_info "Stopping rate limiter (PID: $pid)..."
            kill "$pid" 2>/dev/null
            sleep 1
            kill -9 "$pid" 2>/dev/null || true
            log_ok "Rate limiter stopped"
        fi
        rm -f "$RATE_LIMITER_PID_FILE"
    else
        log_warn "Rate limiter not running"
    fi

    # Stop llama-server
    ./start-llm-server.sh stop

    log_ok "All services stopped"
}

show_status() {
    print_header "Service Status"

    # llama-server status
    echo -e "${CYAN}llama-server:${NC}"
    if pgrep -f "llama-server.*--port $BACKEND_PORT" > /dev/null; then
        local pid=$(pgrep -f "llama-server.*--port $BACKEND_PORT")
        local health=$(curl -s "http://localhost:$BACKEND_PORT/health" 2>/dev/null || echo '{"status":"error"}')
        echo -e "  Status: ${GREEN}running${NC} (PID: $pid)"
        echo -e "  Health: $health"
    else
        echo -e "  Status: ${RED}stopped${NC}"
    fi
    echo ""

    # Rate limiter status
    echo -e "${CYAN}Rate Limiter:${NC}"
    if [[ -f "$RATE_LIMITER_PID_FILE" ]] && kill -0 "$(cat "$RATE_LIMITER_PID_FILE")" 2>/dev/null; then
        local pid=$(cat "$RATE_LIMITER_PID_FILE")
        local stats=$(curl -s "http://localhost:$PROXY_PORT/proxy/stats" 2>/dev/null || echo '{"error":"not responding"}')
        echo -e "  Status: ${GREEN}running${NC} (PID: $pid)"
        echo -e "  Stats: $stats"
    else
        echo -e "  Status: ${RED}stopped${NC}"
    fi
    echo ""

    # Show endpoints
    echo -e "${CYAN}Endpoints:${NC}"
    echo "  API (rate limited): http://localhost:$PROXY_PORT/v1"
    echo "  Backend (direct):   http://localhost:$BACKEND_PORT/v1"
}

show_help() {
    echo "Start LLM Server with Rate Limiting"
    echo ""
    echo "Usage: $0 [command] [model_name]"
    echo ""
    echo "Commands:"
    echo "  [model_name]   Start server with rate limiting (default: qwen3-235b-thinking)"
    echo "  stop           Stop all services"
    echo "  status         Show service status"
    echo "  help           Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                           # Start default model with rate limiting"
    echo "  $0 qwen3-235b-thinking       # Start specific model"
    echo "  $0 status                    # Check status"
    echo "  $0 stop                      # Stop everything"
}

# Main
case "${1:-}" in
    stop)
        stop_server
        ;;
    status)
        show_status
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        start_server "${1:-qwen3-235b-thinking}"
        ;;
esac
