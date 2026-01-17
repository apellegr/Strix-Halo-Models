#!/bin/bash

#===============================================================================
# GPU Crash Catcher for Strix Halo
#===============================================================================
# Monitors kernel log for GPU errors and captures detailed system state
# when a crash is detected. Useful for debugging GPU stability issues.
#
# Usage:
#   ./crash-catcher.sh              # Start monitoring
#   ./crash-catcher.sh --test       # Trigger a test capture
#===============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
RESULTS_DIR="${RESULTS_DIR:-$SCRIPT_DIR/crash-reports}"

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
# Crash Patterns
#===============================================================================

# Patterns that indicate GPU problems
CRASH_PATTERNS=(
    "amdgpu.*error"
    "amdgpu.*failed"
    "gpu.*reset"
    "device.*wedged"
    "MES.*failed"
    "ib.*test.*failed"
    "ring.*timeout"
    "fence.*timeout"
    "gpu.*hang"
    "amdgpu.*timeout"
)

# Build grep pattern
build_pattern() {
    local pattern=""
    for p in "${CRASH_PATTERNS[@]}"; do
        if [[ -n "$pattern" ]]; then
            pattern+="|"
        fi
        pattern+="$p"
    done
    echo "$pattern"
}

#===============================================================================
# Capture Functions
#===============================================================================

capture_crash_report() {
    local trigger_msg="$1"
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local report_file="$RESULTS_DIR/crash-${timestamp}.txt"

    mkdir -p "$RESULTS_DIR"

    echo -e "${RED}!!! GPU CRASH DETECTED !!!${NC}"
    echo "Capturing crash report to: $report_file"

    {
        echo "==============================================================================="
        echo "GPU CRASH REPORT"
        echo "==============================================================================="
        echo ""
        echo "Timestamp: $(date)"
        echo "Trigger: $trigger_msg"
        echo ""

        echo "==============================================================================="
        echo "KERNEL LOG (last 100 GPU-related lines)"
        echo "==============================================================================="
        journalctl -k --no-pager -n 500 2>/dev/null | grep -i -E "(amdgpu|gpu|drm|rocm)" | tail -100
        echo ""

        echo "==============================================================================="
        echo "FULL KERNEL LOG (last 5 minutes)"
        echo "==============================================================================="
        journalctl -k --since "5 minutes ago" --no-pager 2>/dev/null | tail -200
        echo ""

        echo "==============================================================================="
        echo "GPU STATUS (rocm-smi)"
        echo "==============================================================================="
        rocm-smi 2>&1 || echo "rocm-smi failed or not available"
        echo ""

        echo "==============================================================================="
        echo "GPU MEMORY INFO"
        echo "==============================================================================="
        rocm-smi --showmeminfo vram 2>&1 || echo "Could not get VRAM info"
        echo ""
        cat /sys/class/drm/card0/device/mem_info_vram_used 2>/dev/null && echo " bytes VRAM used"
        cat /sys/class/drm/card0/device/mem_info_gtt_used 2>/dev/null && echo " bytes GTT used"
        echo ""

        echo "==============================================================================="
        echo "GPU DEVICE INFO"
        echo "==============================================================================="
        cat /sys/class/drm/card0/device/gpu_busy_percent 2>/dev/null && echo "% GPU busy"
        cat /sys/class/drm/card0/device/current_link_speed 2>/dev/null || true
        cat /sys/class/drm/card0/device/current_link_width 2>/dev/null || true
        echo ""

        echo "==============================================================================="
        echo "SYSTEM MEMORY"
        echo "==============================================================================="
        free -h
        echo ""
        cat /proc/meminfo | head -20
        echo ""

        echo "==============================================================================="
        echo "LLM SERVER PROCESSES"
        echo "==============================================================================="
        ps aux | grep -E "(llama-server|llama-cli)" | grep -v grep || echo "No llama processes"
        echo ""

        echo "==============================================================================="
        echo "LLM SERVER LOGS (last 50 lines)"
        echo "==============================================================================="
        for logfile in ~/.llm-servers/*.log; do
            if [[ -f "$logfile" ]]; then
                echo "--- $(basename "$logfile") ---"
                tail -50 "$logfile"
                echo ""
            fi
        done

        echo "==============================================================================="
        echo "CPU INFO"
        echo "==============================================================================="
        uptime
        echo ""
        cat /proc/loadavg
        echo ""

        echo "==============================================================================="
        echo "TEMPERATURE SENSORS"
        echo "==============================================================================="
        sensors 2>/dev/null || echo "sensors not available"
        echo ""

        echo "==============================================================================="
        echo "DEVCOREDUMP (if available)"
        echo "==============================================================================="
        if [[ -f /sys/class/drm/card0/device/devcoredump/data ]]; then
            echo "Devcoredump exists - first 100 lines:"
            head -100 /sys/class/drm/card0/device/devcoredump/data 2>/dev/null || echo "Could not read devcoredump"
        else
            echo "No devcoredump available"
        fi
        echo ""

        echo "==============================================================================="
        echo "END OF CRASH REPORT"
        echo "==============================================================================="

    } > "$report_file" 2>&1

    echo -e "${GREEN}Crash report saved to: $report_file${NC}"

    # Also save a compact summary
    local summary_file="$RESULTS_DIR/crash-${timestamp}-summary.txt"
    {
        echo "GPU Crash Summary - $(date)"
        echo "Trigger: $trigger_msg"
        echo ""
        echo "Recent GPU errors:"
        journalctl -k --since "2 minutes ago" --no-pager 2>/dev/null | grep -i -E "(error|fail|reset|wedged|timeout)" | tail -20
    } > "$summary_file"

    return 0
}

#===============================================================================
# Monitor Functions
#===============================================================================

monitor_crashes() {
    local pattern=$(build_pattern)

    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}  GPU Crash Catcher${NC}"
    echo -e "${CYAN}════════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo "Monitoring kernel log for GPU errors..."
    echo "Reports will be saved to: $RESULTS_DIR/"
    echo "Press Ctrl+C to stop"
    echo ""
    echo -e "${GREEN}Watching for patterns:${NC}"
    for p in "${CRASH_PATTERNS[@]}"; do
        echo "  - $p"
    done
    echo ""

    mkdir -p "$RESULTS_DIR"

    # Track last seen error to avoid duplicates
    local last_error=""
    local last_error_time=0

    while true; do
        # Check for new errors in the last 5 seconds
        local errors
        errors=$(journalctl -k --since "5 seconds ago" --no-pager 2>/dev/null | grep -i -E "$pattern" | head -1)

        if [[ -n "$errors" ]]; then
            local current_time=$(date +%s)

            # Deduplicate - don't capture the same error within 30 seconds
            if [[ "$errors" != "$last_error" || $((current_time - last_error_time)) -gt 30 ]]; then
                last_error="$errors"
                last_error_time=$current_time
                capture_crash_report "$errors"
            fi
        fi

        sleep 2
    done
}

#===============================================================================
# Main
#===============================================================================

show_help() {
    cat << EOF
GPU Crash Catcher for Strix Halo

Usage: $0 [options]

Options:
  --test           Capture a test report (simulates crash detection)
  --list           List existing crash reports
  --view REPORT    View a specific crash report
  --help           Show this help

Examples:
  $0                    # Start monitoring for crashes
  $0 --test             # Generate a test crash report
  $0 --list             # List all crash reports

The crash catcher monitors the kernel log for GPU errors and automatically
captures detailed system state when problems are detected. This helps debug
what conditions lead to GPU crashes.

Crash reports include:
  - Kernel log excerpts
  - GPU status and memory info
  - System memory state
  - LLM server process info
  - Temperature readings
  - Devcoredump data (if available)
EOF
}

main() {
    case "${1:-}" in
        --test|-t)
            echo "Generating test crash report..."
            capture_crash_report "TEST - Manual trigger"
            ;;
        --list|-l)
            echo "Crash reports in $RESULTS_DIR/:"
            ls -la "$RESULTS_DIR"/crash-*.txt 2>/dev/null || echo "No crash reports found"
            ;;
        --view|-v)
            if [[ -f "$2" ]]; then
                less "$2"
            elif [[ -f "$RESULTS_DIR/$2" ]]; then
                less "$RESULTS_DIR/$2"
            else
                echo "Report not found: $2"
                exit 1
            fi
            ;;
        --help|-h)
            show_help
            ;;
        "")
            # Trap for clean exit
            trap 'echo ""; echo "Crash catcher stopped."; exit 0' INT TERM
            monitor_crashes
            ;;
        *)
            echo "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
}

main "$@"
