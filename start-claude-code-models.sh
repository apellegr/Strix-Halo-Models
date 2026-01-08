#!/bin/bash

#===============================================================================
# Start Models for Claude Code Router
#===============================================================================
# Starts the optimized model configuration for use with Claude Code:
#   - llama-3.2-3b (port 8081) - background tasks (titles, topics)
#   - qwen2.5-coder-32b (port 8082) - main coding tasks
#   - deepseek-r1-32b (port 8083) - complex reasoning
#
# Usage:
#   ./start-claude-code-models.sh          # Start all models
#   ./start-claude-code-models.sh stop     # Stop all models
#   ./start-claude-code-models.sh status   # Check status
#   ./start-claude-code-models.sh router   # Start router too
#===============================================================================

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "\n${CYAN}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  $1${NC}"
    echo -e "${CYAN}══════════════════════════════════════════════════════════════${NC}\n"
}

print_info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[OK]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARN]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

# Models configuration for Claude Code
# Format: model_name:port:role
CLAUDE_CODE_MODELS=(
    "llama-3.2-3b:8081:background"
    "hermes-4-14b:8082:default"
    "hermes-4-70b:8083:reasoning"
)

start_models() {
    print_header "Starting Claude Code Models"

    local failed=0

    for model_config in "${CLAUDE_CODE_MODELS[@]}"; do
        IFS=':' read -r model_name port role <<< "$model_config"

        print_info "Starting $model_name on port $port ($role)..."

        if ! "$SCRIPT_DIR/start-llm-server.sh" "$model_name" "$port"; then
            print_error "Failed to start $model_name"
            failed=$((failed + 1))
        fi

        echo ""
    done

    if [[ $failed -gt 0 ]]; then
        print_warning "$failed model(s) failed to start"
        return 1
    fi

    print_success "All models started"
    show_summary
}

stop_models() {
    print_header "Stopping Claude Code Models"

    "$SCRIPT_DIR/start-llm-server.sh" stop

    print_success "All models stopped"
}

show_status() {
    "$SCRIPT_DIR/start-llm-server.sh" status
}

start_router() {
    print_header "Starting Claude Code Router"

    # Check if router is already running
    if curl -s http://localhost:3456/health &>/dev/null; then
        print_warning "Router is already running"
        return 0
    fi

    # Try to start router
    if command -v ccr &>/dev/null; then
        print_info "Starting router with ccr..."
        nohup ccr start > /tmp/ccr.log 2>&1 &
    else
        # Try to find it in npm global
        local CCR_PATH="$HOME/.npm-global/lib/node_modules/@musistudio/claude-code-router/dist/cli.js"
        if [[ -f "$CCR_PATH" ]]; then
            print_info "Starting router from npm global..."
            cd "$(dirname "$CCR_PATH")/.." && nohup node dist/cli.js start > /tmp/ccr.log 2>&1 &
        else
            print_error "Claude Code Router not found. Run: ./claude-code-router/install.sh"
            return 1
        fi
    fi

    # Wait for router to start
    local timeout=10
    local elapsed=0
    while [[ $elapsed -lt $timeout ]]; do
        if curl -s http://localhost:3456/health &>/dev/null; then
            print_success "Router started on port 3456"
            return 0
        fi
        sleep 1
        elapsed=$((elapsed + 1))
    done

    print_error "Router failed to start. Check /tmp/ccr.log"
    return 1
}

show_summary() {
    echo ""
    print_header "Claude Code Configuration"

    echo "Models running:"
    for model_config in "${CLAUDE_CODE_MODELS[@]}"; do
        IFS=':' read -r model_name port role <<< "$model_config"
        echo "  Port $port: $model_name ($role)"
    done
    echo ""

    # Check router
    if curl -s http://localhost:3456/health &>/dev/null; then
        echo -e "Router: ${GREEN}running${NC} on port 3456"
    else
        echo -e "Router: ${RED}not running${NC}"
        echo "  Start with: $0 router"
    fi

    echo ""
    echo "To use with Claude Code:"
    echo "  export ANTHROPIC_BASE_URL=http://localhost:3456"
    echo "  claude"
    echo ""
}

show_help() {
    echo "Start Models for Claude Code Router"
    echo ""
    echo "Usage: $0 [command]"
    echo ""
    echo "Commands:"
    echo "  (none)     Start all models"
    echo "  stop       Stop all models"
    echo "  status     Show status of all models"
    echo "  router     Start the Claude Code Router"
    echo "  all        Start models and router"
    echo "  help       Show this help"
    echo ""
    echo "Models started:"
    for model_config in "${CLAUDE_CODE_MODELS[@]}"; do
        IFS=':' read -r model_name role <<< "$model_config"
        echo "  - $model_name ($role)"
    done
    echo ""
}

#===============================================================================
# Main
#===============================================================================

case "${1:-start}" in
    start)
        start_models
        ;;
    stop)
        stop_models
        ;;
    status)
        show_status
        ;;
    router)
        start_router
        ;;
    all)
        start_models
        start_router
        ;;
    help|--help|-h)
        show_help
        ;;
    *)
        print_error "Unknown command: $1"
        show_help
        exit 1
        ;;
esac
