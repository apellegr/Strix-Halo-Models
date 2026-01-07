#!/bin/bash
# system-status.sh - Monitor AMD Strix Halo system status
# Shows GPU/CPU config, temperatures, power, and running models

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default settings
WATCH_MODE=false
INTERVAL=1
SHOW_HELP=false

# State directory for tracking metrics between refreshes (persistent across runs)
STATE_DIR="/tmp/system-status-metrics"
mkdir -p "$STATE_DIR"

# Cleanup old state files on exit (only in non-watch mode)
cleanup() {
    if ! $WATCH_MODE; then
        # Keep state files for 60 seconds to allow rapid re-runs
        find "$STATE_DIR" -type f -mmin +1 -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--watch)
            WATCH_MODE=true
            shift
            ;;
        -i|--interval)
            INTERVAL="$2"
            shift 2
            ;;
        -h|--help)
            SHOW_HELP=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

if $SHOW_HELP; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Monitor AMD Strix Halo system status including GPU/CPU configuration,"
    echo "temperatures, power consumption, and running LLM models."
    echo ""
    echo "Options:"
    echo "  -w, --watch         Continuously refresh the display"
    echo "  -i, --interval SEC  Refresh interval in seconds (default: 1)"
    echo "  -h, --help          Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0                  Show single snapshot"
    echo "  $0 -w               Watch mode with 1 second refresh"
    echo "  $0 -w -i 2          Watch mode with 2 second refresh"
    exit 0
fi

# Function to read GPU clock from pp_dpm file
read_dpm_clock() {
    local file=$1
    grep '\*' "$file" 2>/dev/null | awk '{print $2}' | head -1
}

# GPU sysfs paths
GPU_PATH="/sys/class/drm/card0/device"
GPU_HWMON="/sys/class/drm/card0/device/hwmon/hwmon5"

# Function to get running models (returns: model|port|ctx|cpu|mem|pid)
get_running_models() {
    ps aux 2>/dev/null | grep -E 'llama-server|ollama|vllm' | grep -v grep | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local model=$(echo "$line" | grep -oP '(?<=--alias )[^ ]+' || echo "unknown")
        local port=$(echo "$line" | grep -oP '(?<=--port )[^ ]+' || echo "?")
        local ctx=$(echo "$line" | grep -oP '(?<=--ctx-size )[^ ]+' || echo "?")
        echo "$model|$port|$ctx|$cpu|$mem|$pid"
    done
}

# Function to get token metrics from a model's /metrics endpoint
# Returns: prompt_tokens|generated_tokens|prompt_seconds|generated_seconds
get_model_metrics() {
    local port=$1
    local metrics=$(curl -s --max-time 1 "http://localhost:$port/metrics" 2>/dev/null)

    if [[ -z "$metrics" ]] || echo "$metrics" | grep -q '"error"'; then
        echo "N/A|N/A|N/A|N/A"
        return
    fi

    # Parse Prometheus-style metrics
    local prompt_tokens=$(echo "$metrics" | grep '^llamacpp:prompt_tokens_total' | awk '{print $2}' | head -1)
    local gen_tokens=$(echo "$metrics" | grep '^llamacpp:tokens_predicted_total' | awk '{print $2}' | head -1)
    local prompt_seconds=$(echo "$metrics" | grep '^llamacpp:prompt_seconds_total' | awk '{print $2}' | head -1)
    local gen_seconds=$(echo "$metrics" | grep '^llamacpp:tokens_predicted_seconds_total' | awk '{print $2}' | head -1)

    echo "${prompt_tokens:-0}|${gen_tokens:-0}|${prompt_seconds:-0}|${gen_seconds:-0}"
}

# Function to calculate instantaneous tok/s using delta from previous reading
# Returns: in_tps|out_tps (instantaneous tokens per second)
get_instantaneous_tps() {
    local model=$1
    local prompt_tok=$2
    local gen_tok=$3
    local current_time=$(date +%s.%N)

    local state_file="$STATE_DIR/${model}.state"

    # Default to N/A if no previous state
    local in_tps="--"
    local out_tps="--"

    if [[ -f "$state_file" ]]; then
        # Read previous state
        IFS='|' read -r prev_prompt prev_gen prev_time < "$state_file"

        # Calculate time delta
        local time_delta=$(awk "BEGIN {printf \"%.3f\", $current_time - $prev_time}")

        # Only calculate if we have a meaningful time delta (> 0.1s)
        if (( $(awk "BEGIN {print ($time_delta > 0.1) ? 1 : 0}") )); then
            # Calculate token deltas
            local prompt_delta=$(awk "BEGIN {print $prompt_tok - $prev_prompt}")
            local gen_delta=$(awk "BEGIN {print $gen_tok - $prev_gen}")

            # Calculate instantaneous tok/s
            if (( $(awk "BEGIN {print ($prompt_delta > 0) ? 1 : 0}") )); then
                in_tps=$(awk "BEGIN {printf \"%.1f\", $prompt_delta / $time_delta}")
            else
                in_tps="0.0"
            fi

            if (( $(awk "BEGIN {print ($gen_delta > 0) ? 1 : 0}") )); then
                out_tps=$(awk "BEGIN {printf \"%.1f\", $gen_delta / $time_delta}")
            else
                out_tps="0.0"
            fi
        fi
    fi

    # Save current state for next iteration
    echo "$prompt_tok|$gen_tok|$current_time" > "$state_file"

    echo "$in_tps|$out_tps"
}

# Function to format large numbers with K/M suffix
format_number() {
    local num=$1
    if [[ "$num" == "N/A" ]] || [[ -z "$num" ]]; then
        echo "N/A"
        return
    fi

    # Remove decimal part for comparison
    local int_num=${num%.*}

    if [[ $int_num -ge 1000000 ]]; then
        awk "BEGIN {printf \"%.1fM\", $num / 1000000}"
    elif [[ $int_num -ge 1000 ]]; then
        awk "BEGIN {printf \"%.1fK\", $num / 1000}"
    else
        echo "$int_num"
    fi
}

# Function to create a visual progress bar
# Usage: progress_bar <percentage> <width> <filled_char> <empty_char>
progress_bar() {
    local percent=$1
    local width=${2:-20}
    local filled_char=${3:-"█"}
    local empty_char=${4:-"░"}

    # Handle non-numeric or empty values
    if [[ -z "$percent" ]] || ! [[ "$percent" =~ ^[0-9]+$ ]]; then
        percent=0
    fi

    local filled=$((percent * width / 100))
    local empty=$((width - filled))

    local bar=""
    for ((i=0; i<filled; i++)); do bar+="$filled_char"; done
    for ((i=0; i<empty; i++)); do bar+="$empty_char"; done

    echo "$bar"
}

# Function to get CPU utilization percentage
# Uses /proc/stat to calculate CPU usage with a brief sample interval
get_cpu_utilization() {
    # Read first sample
    local cpu_line1=$(head -1 /proc/stat)
    local user1=$(echo "$cpu_line1" | awk '{print $2}')
    local nice1=$(echo "$cpu_line1" | awk '{print $3}')
    local system1=$(echo "$cpu_line1" | awk '{print $4}')
    local idle1=$(echo "$cpu_line1" | awk '{print $5}')
    local iowait1=$(echo "$cpu_line1" | awk '{print $6}')
    local irq1=$(echo "$cpu_line1" | awk '{print $7}')
    local softirq1=$(echo "$cpu_line1" | awk '{print $8}')

    # Brief delay for sampling
    sleep 0.1

    # Read second sample
    local cpu_line2=$(head -1 /proc/stat)
    local user2=$(echo "$cpu_line2" | awk '{print $2}')
    local nice2=$(echo "$cpu_line2" | awk '{print $3}')
    local system2=$(echo "$cpu_line2" | awk '{print $4}')
    local idle2=$(echo "$cpu_line2" | awk '{print $5}')
    local iowait2=$(echo "$cpu_line2" | awk '{print $6}')
    local irq2=$(echo "$cpu_line2" | awk '{print $7}')
    local softirq2=$(echo "$cpu_line2" | awk '{print $8}')

    local total1=$((user1 + nice1 + system1 + idle1 + iowait1 + irq1 + softirq1))
    local total2=$((user2 + nice2 + system2 + idle2 + iowait2 + irq2 + softirq2))
    local busy1=$((user1 + nice1 + system1 + irq1 + softirq1))
    local busy2=$((user2 + nice2 + system2 + irq2 + softirq2))

    # Calculate delta
    local diff_total=$((total2 - total1))
    local diff_busy=$((busy2 - busy1))

    # Calculate percentage (avoid division by zero)
    if [[ $diff_total -gt 0 ]]; then
        echo $((diff_busy * 100 / diff_total))
    else
        echo "0"
    fi
}

# Function to display status
display_status() {
    # Clear screen in watch mode
    if $WATCH_MODE; then
        clear
    fi

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║          AMD Strix Halo System Status - $timestamp          ║${NC}"
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════╝${NC}"
    echo ""

    # GPU Section - read values directly
    local gpu_clock=$(read_dpm_clock "$GPU_PATH/pp_dpm_sclk")
    local gpu_fclk=$(read_dpm_clock "$GPU_PATH/pp_dpm_fclk")
    local gpu_socclk=$(read_dpm_clock "$GPU_PATH/pp_dpm_socclk")
    local gpu_mclk=$(read_dpm_clock "$GPU_PATH/pp_dpm_mclk")
    local gpu_perf=$(cat "$GPU_PATH/power_dpm_force_performance_level" 2>/dev/null)
    local gpu_busy=$(cat "$GPU_PATH/gpu_busy_percent" 2>/dev/null || echo "0")
    local gpu_power_uw=$(cat "$GPU_HWMON/power1_average" 2>/dev/null || echo "0")
    local gpu_power=$(awk "BEGIN {printf \"%.1f\", $gpu_power_uw / 1000000}")
    local gpu_temp_mc=$(cat "$GPU_HWMON/temp1_input" 2>/dev/null || echo "0")
    local gpu_temp=$(awk "BEGIN {printf \"%.1f\", $gpu_temp_mc / 1000}")

    # Get memory bandwidth utilization if available
    local mem_busy=$(cat "$GPU_PATH/mem_busy_percent" 2>/dev/null || echo "0")

    # Create utilization bar with color based on usage
    local gpu_bar=$(progress_bar "$gpu_busy" 20)
    local util_color=$GREEN
    if [[ "$gpu_busy" -ge 80 ]]; then
        util_color=$RED
    elif [[ "$gpu_busy" -ge 50 ]]; then
        util_color=$YELLOW
    fi

    echo -e "${CYAN}${BOLD}┌─ GPU (Radeon 8060S) ─────────────────────────────────────────────┐${NC}"
    printf "${CYAN}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${CYAN}│${NC}\n" "Clock:" "$gpu_clock" "Fabric Clock:" "$gpu_fclk"
    printf "${CYAN}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${CYAN}│${NC}\n" "SOC Clock:" "$gpu_socclk" "Memory Clock:" "$gpu_mclk"
    printf "${CYAN}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${CYAN}│${NC}\n" "Performance Level:" "$gpu_perf" "Mem Bandwidth:" "${mem_busy}%"

    # GPU Utilization with visual bar
    printf "${CYAN}│${NC} %-20s ${util_color}%-6s${NC} ${util_color}%s${NC} %-22s ${CYAN}│${NC}\n" "GPU Utilization:" "${gpu_busy}%" "$gpu_bar" ""

    # Color temperature based on value
    local temp_color=$GREEN
    if (( $(echo "$gpu_temp > 80" | bc -l 2>/dev/null || echo 0) )); then
        temp_color=$RED
    elif (( $(echo "$gpu_temp > 70" | bc -l 2>/dev/null || echo 0) )); then
        temp_color=$YELLOW
    fi
    printf "${CYAN}│${NC} %-20s ${temp_color}%-15s${NC} %-20s ${YELLOW}%-10s${NC} ${CYAN}│${NC}\n" "Temperature:" "${gpu_temp}°C" "Power:" "${gpu_power}W"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # CPU Section
    local cpu_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    local cpu_freq_sum=0
    local cpu_count=0
    for freq_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        if [[ -f "$freq_file" ]]; then
            local freq=$(cat "$freq_file" 2>/dev/null || echo "0")
            cpu_freq_sum=$((cpu_freq_sum + freq))
            cpu_count=$((cpu_count + 1))
        fi
    done
    local cpu_freq=$((cpu_freq_sum / cpu_count / 1000))
    local cpu_temp_mc=$(cat /sys/class/hwmon/hwmon3/temp1_input 2>/dev/null || echo "0")
    local cpu_temp=$(awk "BEGIN {printf \"%.1f\", $cpu_temp_mc / 1000}")

    # Get CPU utilization
    local cpu_util=$(get_cpu_utilization)
    local cpu_bar=$(progress_bar "$cpu_util" 20)
    local cpu_util_color=$GREEN
    if [[ "$cpu_util" -ge 80 ]]; then
        cpu_util_color=$RED
    elif [[ "$cpu_util" -ge 50 ]]; then
        cpu_util_color=$YELLOW
    fi

    echo -e "${BLUE}${BOLD}┌─ CPU (Ryzen AI MAX+ 395) ────────────────────────────────────────┐${NC}"
    printf "${BLUE}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${BLUE}│${NC}\n" "Governor:" "$cpu_gov" "Avg Frequency:" "${cpu_freq}MHz"

    # CPU Utilization with visual bar
    printf "${BLUE}│${NC} %-20s ${cpu_util_color}%-6s${NC} ${cpu_util_color}%s${NC} %-22s ${BLUE}│${NC}\n" "CPU Utilization:" "${cpu_util}%" "$cpu_bar" ""

    # Color temperature based on value
    temp_color=$GREEN
    if (( $(echo "$cpu_temp > 90" | bc -l 2>/dev/null || echo 0) )); then
        temp_color=$RED
    elif (( $(echo "$cpu_temp > 80" | bc -l 2>/dev/null || echo 0) )); then
        temp_color=$YELLOW
    fi
    printf "${BLUE}│${NC} %-20s ${temp_color}%-15s${NC} %-20s %-10s ${BLUE}│${NC}\n" "Temperature:" "${cpu_temp}°C" "" ""
    echo -e "${BLUE}└───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Memory Section
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    local mem_used=$(free -g | awk '/^Mem:/{print $3}')
    local mem_percent=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
    local vram_total=$(($(cat "$GPU_PATH/mem_info_vram_total" 2>/dev/null || echo 0) / 1024 / 1024))
    local vram_used=$(($(cat "$GPU_PATH/mem_info_vram_used" 2>/dev/null || echo 0) / 1024 / 1024))
    local gtt_total=$(($(cat "$GPU_PATH/mem_info_gtt_total" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
    local gtt_used=$(($(cat "$GPU_PATH/mem_info_gtt_used" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))

    echo -e "${YELLOW}${BOLD}┌─ Memory ──────────────────────────────────────────────────────────┐${NC}"
    printf "${YELLOW}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${YELLOW}│${NC}\n" "System RAM:" "${mem_used}GB / ${mem_total}GB" "Usage:" "${mem_percent}%"
    printf "${YELLOW}│${NC} %-20s ${GREEN}%-15s${NC} %-20s ${GREEN}%-10s${NC} ${YELLOW}│${NC}\n" "VRAM:" "${vram_used}MB / ${vram_total}MB" "GTT:" "${gtt_used}GB / ${gtt_total}GB"
    echo -e "${YELLOW}└───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Running Models Section
    echo -e "${GREEN}${BOLD}┌─ Running Models ──────────────────────────────────────────────────┐${NC}"
    printf "${GREEN}│${NC} ${BOLD}%-20s %-6s %-7s %-6s %-6s${NC} ${GREEN}│${NC}\n" "Model" "Port" "Ctx" "CPU%" "MEM%"
    echo -e "${GREEN}│${NC} ─────────────────────────────────────────────────────────────────── ${GREEN}│${NC}"

    local model_count=0
    local models_data=""
    while IFS='|' read -r model port ctx cpu mem pid; do
        if [[ -n "$model" ]]; then
            printf "${GREEN}│${NC} %-20s %-6s %-7s %-6s %-6s ${GREEN}│${NC}\n" "$model" "$port" "$ctx" "$cpu" "$mem"
            models_data+="$model|$port|$ctx|$cpu|$mem|$pid"$'\n'
            model_count=$((model_count + 1))
        fi
    done <<< "$(get_running_models)"

    if [[ $model_count -eq 0 ]]; then
        printf "${GREEN}│${NC} %-67s ${GREEN}│${NC}\n" "No models currently running"
    fi
    echo -e "${GREEN}└───────────────────────────────────────────────────────────────────┘${NC}"
    echo ""

    # Token Statistics Section (only if models are running)
    if [[ $model_count -gt 0 ]]; then
        echo -e "${CYAN}${BOLD}┌─ Token Statistics ────────────────────────────────────────────────┐${NC}"
        printf "${CYAN}│${NC} ${BOLD}%-18s %-9s %-9s %-11s %-11s${NC} ${CYAN}│${NC}\n" "Model" "In Tok" "Out Tok" "In tok/s" "Out tok/s"
        echo -e "${CYAN}│${NC} ─────────────────────────────────────────────────────────────────── ${CYAN}│${NC}"

        local has_metrics=false
        while IFS='|' read -r model port ctx cpu mem pid; do
            if [[ -n "$model" ]] && [[ "$port" != "?" ]]; then
                IFS='|' read -r prompt_tok gen_tok prompt_sec gen_sec <<< "$(get_model_metrics "$port")"

                if [[ "$prompt_tok" != "N/A" ]]; then
                    has_metrics=true

                    # Get instantaneous tok/s (delta-based)
                    IFS='|' read -r in_tps out_tps <<< "$(get_instantaneous_tps "$model" "$prompt_tok" "$gen_tok")"

                    # Format token counts
                    local fmt_prompt=$(format_number "$prompt_tok")
                    local fmt_gen=$(format_number "$gen_tok")

                    # Color the tok/s based on activity
                    local in_color=$NC
                    local out_color=$NC
                    if [[ "$in_tps" != "--" ]] && [[ "$in_tps" != "0.0" ]]; then
                        in_color=$GREEN
                    fi
                    if [[ "$out_tps" != "--" ]] && [[ "$out_tps" != "0.0" ]]; then
                        out_color=$GREEN
                    fi

                    printf "${CYAN}│${NC} %-18s %-9s %-9s ${in_color}%-11s${NC} ${out_color}%-11s${NC} ${CYAN}│${NC}\n" "$model" "$fmt_prompt" "$fmt_gen" "$in_tps" "$out_tps"
                else
                    printf "${CYAN}│${NC} %-18s ${YELLOW}%-51s${NC} ${CYAN}│${NC}\n" "$model" "(metrics not enabled - restart with --metrics)"
                fi
            fi
        done <<< "$models_data"

        if ! $has_metrics && [[ $model_count -gt 0 ]]; then
            printf "${CYAN}│${NC} ${YELLOW}%-67s${NC} ${CYAN}│${NC}\n" "Restart models to enable metrics (--metrics flag added to script)"
        fi
        echo -e "${CYAN}└───────────────────────────────────────────────────────────────────┘${NC}"
    fi

    if $WATCH_MODE; then
        echo ""
        echo -e "${BOLD}Refreshing every ${INTERVAL}s. Press Ctrl+C to exit.${NC}"
    fi
}

# Main execution
if $WATCH_MODE; then
    trap 'echo -e "\n${GREEN}Exiting...${NC}"; exit 0' INT
    while true; do
        display_status
        sleep "$INTERVAL"
    done
else
    display_status
fi
