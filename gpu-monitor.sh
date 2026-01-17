#!/bin/bash

#===============================================================================
# GPU Monitor for Stress Testing
#===============================================================================
# Continuously monitors GPU state and logs to file. Run alongside stress tests
# to capture GPU conditions when crashes occur.
#
# Usage:
#   ./gpu-monitor.sh                    # Monitor with default interval (2s)
#   ./gpu-monitor.sh --interval 1       # Monitor every 1 second
#   ./gpu-monitor.sh --watch            # Watch mode (updates in place)
#   ./gpu-monitor.sh --log-only         # Log to file only, no console output
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/stress-results}"
LOG_FILE="$RESULTS_DIR/gpu-monitor-$(date +%Y%m%d_%H%M%S).log"

INTERVAL=2
WATCH_MODE=false
LOG_ONLY=false

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
# Monitoring Functions
#===============================================================================

get_timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

get_gpu_utilization() {
    rocm-smi --showuse 2>/dev/null | grep "GPU use" | awk '{print $NF}' | tr -d '%' || echo "0"
}

get_gpu_memory() {
    # Get GTT (system memory used by GPU) which is what matters for Strix Halo
    local vram_used=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Used" | awk '{print $NF}')
    local vram_total=$(rocm-smi --showmeminfo vram 2>/dev/null | grep "Total Memory" | head -1 | awk '{print $NF}')
    echo "${vram_used:-0}|${vram_total:-0}"
}

get_gpu_temp() {
    rocm-smi --showtemp 2>/dev/null | grep -E "Temperature.*edge" | awk '{print $(NF-1)}' | head -1 || echo "?"
}

get_gpu_power() {
    rocm-smi --showpower 2>/dev/null | grep "Average" | awk '{print $(NF-1)}' || echo "?"
}

get_gpu_clock() {
    rocm-smi --showclocks 2>/dev/null | grep "sclk" | head -1 | awk '{print $(NF-1)}' || echo "?"
}

get_system_memory() {
    free -b | awk '/Mem:/ {printf "%.1f|%.1f|%.1f", $3/1024/1024/1024, $2/1024/1024/1024, $7/1024/1024/1024}'
}

get_llama_memory() {
    # Get memory used by llama-server processes
    local total_kb=0
    while read -r rss; do
        total_kb=$((total_kb + rss))
    done < <(pgrep -f "llama-server" | xargs -I{} ps -o rss= -p {} 2>/dev/null)
    echo "scale=1; $total_kb / 1024 / 1024" | bc
}

check_kernel_errors() {
    # Check for recent GPU errors in kernel log
    journalctl -k --since "10 seconds ago" --no-pager 2>/dev/null | grep -i -E "(amdgpu.*error|gpu.*reset|wedged|MES.*failed|timeout)" | head -3
}

#===============================================================================
# Display Functions
#===============================================================================

print_status_line() {
    local timestamp=$(get_timestamp)
    local gpu_use=$(get_gpu_utilization)
    local gpu_temp=$(get_gpu_temp)
    local gpu_power=$(get_gpu_power)
    local gpu_clock=$(get_gpu_clock)

    IFS='|' read -r vram_used vram_total <<< "$(get_gpu_memory)"
    IFS='|' read -r sys_used sys_total sys_avail <<< "$(get_system_memory)"
    local llama_mem=$(get_llama_memory)

    # Format VRAM (convert bytes to MB)
    local vram_used_mb=$(echo "scale=0; $vram_used / 1024 / 1024" | bc 2>/dev/null || echo "?")
    local vram_total_mb=$(echo "scale=0; $vram_total / 1024 / 1024" | bc 2>/dev/null || echo "?")

    # Log line
    echo "[$timestamp] GPU: ${gpu_use}% | Temp: ${gpu_temp}C | Power: ${gpu_power}W | Clock: ${gpu_clock}MHz | VRAM: ${vram_used_mb}/${vram_total_mb}MB | RAM: ${sys_used}/${sys_total}GB (${sys_avail}GB free) | LLM: ${llama_mem}GB" >> "$LOG_FILE"

    # Console output
    if [[ "$LOG_ONLY" != "true" ]]; then
        if [[ "$WATCH_MODE" == "true" ]]; then
            # Clear line and print
            printf "\r\033[K"
        fi

        # Color code GPU usage
        local gpu_color="$GREEN"
        if [[ "$gpu_use" -gt 80 ]]; then
            gpu_color="$RED"
        elif [[ "$gpu_use" -gt 50 ]]; then
            gpu_color="$YELLOW"
        fi

        # Color code temperature
        local temp_color="$GREEN"
        if [[ "${gpu_temp%.*}" -gt 80 ]]; then
            temp_color="$RED"
        elif [[ "${gpu_temp%.*}" -gt 65 ]]; then
            temp_color="$YELLOW"
        fi

        printf "${CYAN}%s${NC} | GPU: ${gpu_color}%3s%%${NC} | Temp: ${temp_color}%sC${NC} | Power: %sW | RAM: %s/%sGB | LLM: %sGB" \
            "$timestamp" "$gpu_use" "$gpu_temp" "$gpu_power" "$sys_used" "$sys_total" "$llama_mem"

        if [[ "$WATCH_MODE" != "true" ]]; then
            echo ""
        fi
    fi

    # Check for kernel errors
    local errors=$(check_kernel_errors)
    if [[ -n "$errors" ]]; then
        echo "" >> "$LOG_FILE"
        echo "!!! GPU ERROR DETECTED !!!" >> "$LOG_FILE"
        echo "$errors" >> "$LOG_FILE"
        echo "" >> "$LOG_FILE"

        if [[ "$LOG_ONLY" != "true" ]]; then
            [[ "$WATCH_MODE" == "true" ]] && echo ""
            echo -e "${RED}!!! GPU ERROR DETECTED !!!${NC}"
            echo "$errors"
        fi
    fi
}

print_header() {
    echo ""
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GPU Monitor for Strix Halo${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Log file: $LOG_FILE"
    echo "Interval: ${INTERVAL}s"
    echo "Press Ctrl+C to stop"
    echo ""

    # Log header
    echo "=== GPU Monitor Started ===" >> "$LOG_FILE"
    echo "Timestamp: $(date)" >> "$LOG_FILE"
    echo "Interval: ${INTERVAL}s" >> "$LOG_FILE"
    echo "" >> "$LOG_FILE"
}

print_detailed_status() {
    echo ""
    echo -e "${BLUE}=== Detailed GPU Status ===${NC}"
    rocm-smi 2>/dev/null || echo "rocm-smi not available"
    echo ""

    echo -e "${BLUE}=== Memory Info ===${NC}"
    free -h
    echo ""

    echo -e "${BLUE}=== LLM Server Processes ===${NC}"
    ps aux | grep llama-server | grep -v grep || echo "No llama-server running"
    echo ""
}

#===============================================================================
# Main
#===============================================================================

show_help() {
    cat << EOF
GPU Monitor for Stress Testing

Usage: $0 [options]

Options:
  --interval SEC   Monitoring interval in seconds (default: 2)
  --watch          Watch mode - updates status in place
  --log-only       Log to file only, no console output
  --detailed       Show detailed status once and exit
  --help           Show this help

Examples:
  $0                        # Monitor every 2 seconds
  $0 --interval 1           # Monitor every second
  $0 --watch                # Watch mode with in-place updates
  $0 --log-only &           # Run in background, log only

Output fields:
  GPU%     - GPU utilization percentage
  Temp     - GPU edge temperature in Celsius
  Power    - GPU power consumption in Watts
  VRAM     - Dedicated VRAM usage (small on APU)
  RAM      - System memory used/total
  LLM      - Memory used by llama-server processes

The monitor will highlight GPU errors from the kernel log when they occur.
EOF
}

main() {
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --interval|-i)
                INTERVAL="$2"
                shift 2
                ;;
            --watch|-w)
                WATCH_MODE=true
                shift
                ;;
            --log-only|-l)
                LOG_ONLY=true
                shift
                ;;
            --detailed|-d)
                print_detailed_status
                exit 0
                ;;
            --help|-h)
                show_help
                exit 0
                ;;
            *)
                echo "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    # Setup
    mkdir -p "$RESULTS_DIR"

    # Check for rocm-smi
    if ! command -v rocm-smi &>/dev/null; then
        echo "Warning: rocm-smi not found. GPU metrics will be limited."
    fi

    print_header

    # Trap for clean exit
    trap 'echo ""; echo "Monitor stopped."; echo "=== Monitor Stopped ===" >> "$LOG_FILE"; exit 0' INT TERM

    # Main monitoring loop
    while true; do
        print_status_line
        sleep "$INTERVAL"
    done
}

main "$@"
