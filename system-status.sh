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
DIM='\033[2m'
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

# GPU sysfs paths
GPU_PATH="/sys/class/drm/card0/device"
GPU_HWMON="/sys/class/drm/card0/device/hwmon/hwmon5"

# Function to read GPU clock from pp_dpm file
read_dpm_clock() {
    local file=$1
    grep '\*' "$file" 2>/dev/null | awk '{print $2}' | head -1
}

# Function to get running models (returns: model|port|ctx|cpu|mem|pid|runtime)
get_running_models() {
    ps aux 2>/dev/null | grep -E 'llama-server|ollama|vllm' | grep -v grep | while read -r line; do
        local pid=$(echo "$line" | awk '{print $2}')
        local cpu=$(echo "$line" | awk '{print $3}')
        local mem=$(echo "$line" | awk '{print $4}')
        local model=$(echo "$line" | grep -oP '(?<=--alias )[^ ]+' || echo "unknown")
        local port=$(echo "$line" | grep -oP '(?<=--port )[^ ]+' || echo "?")
        local ctx=$(echo "$line" | grep -oP '(?<=--ctx-size )[^ ]+' || echo "?")
        local runtime=$(ps -p "$pid" -o etime= 2>/dev/null | tr -d ' ')
        echo "$model|$port|$ctx|$cpu|$mem|$pid|$runtime"
    done
}

# Function to get token metrics from a model's /metrics endpoint
get_model_metrics() {
    local port=$1
    local metrics=$(curl -s --max-time 1 "http://localhost:$port/metrics" 2>/dev/null)

    if [[ -z "$metrics" ]] || echo "$metrics" | grep -q '"error"'; then
        echo "N/A|N/A|N/A|N/A"
        return
    fi

    local prompt_tokens=$(echo "$metrics" | grep '^llamacpp:prompt_tokens_total' | awk '{print $2}' | head -1)
    local gen_tokens=$(echo "$metrics" | grep '^llamacpp:tokens_predicted_total' | awk '{print $2}' | head -1)
    local prompt_seconds=$(echo "$metrics" | grep '^llamacpp:prompt_seconds_total' | awk '{print $2}' | head -1)
    local gen_seconds=$(echo "$metrics" | grep '^llamacpp:tokens_predicted_seconds_total' | awk '{print $2}' | head -1)

    echo "${prompt_tokens:-0}|${gen_tokens:-0}|${prompt_seconds:-0}|${gen_seconds:-0}"
}

# Function to calculate instantaneous tok/s
get_instantaneous_tps() {
    local model=$1
    local prompt_tok=$2
    local gen_tok=$3
    local current_time=$(date +%s.%N)
    local state_file="$STATE_DIR/${model}.state"
    local in_tps="--"
    local out_tps="--"

    if [[ -f "$state_file" ]]; then
        IFS='|' read -r prev_prompt prev_gen prev_time < "$state_file"
        local time_delta=$(awk "BEGIN {printf \"%.3f\", $current_time - $prev_time}")

        if (( $(awk "BEGIN {print ($time_delta > 0.1) ? 1 : 0}") )); then
            local prompt_delta=$(awk "BEGIN {print $prompt_tok - $prev_prompt}")
            local gen_delta=$(awk "BEGIN {print $gen_tok - $prev_gen}")

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

    echo "$prompt_tok|$gen_tok|$current_time" > "$state_file"
    echo "$in_tps|$out_tps"
}

# Format large numbers
format_number() {
    local num=$1
    [[ "$num" == "N/A" ]] || [[ -z "$num" ]] && { echo "N/A"; return; }
    local int_num=${num%.*}
    if [[ $int_num -ge 1000000 ]]; then
        awk "BEGIN {printf \"%.1fM\", $num / 1000000}"
    elif [[ $int_num -ge 1000 ]]; then
        awk "BEGIN {printf \"%.1fK\", $num / 1000}"
    else
        echo "$int_num"
    fi
}

# Create progress bar
progress_bar() {
    local percent=$1
    local width=${2:-20}
    [[ -z "$percent" ]] || ! [[ "$percent" =~ ^[0-9]+$ ]] && percent=0
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

# Get CPU utilization
get_cpu_utilization() {
    local cpu_line1=$(head -1 /proc/stat)
    local vals1=($cpu_line1)
    sleep 0.1
    local cpu_line2=$(head -1 /proc/stat)
    local vals2=($cpu_line2)

    local total1=$((vals1[1] + vals1[2] + vals1[3] + vals1[4] + vals1[5] + vals1[6] + vals1[7]))
    local total2=$((vals2[1] + vals2[2] + vals2[3] + vals2[4] + vals2[5] + vals2[6] + vals2[7]))
    local busy1=$((vals1[1] + vals1[2] + vals1[3] + vals1[6] + vals1[7]))
    local busy2=$((vals2[1] + vals2[2] + vals2[3] + vals2[6] + vals2[7]))

    local diff_total=$((total2 - total1))
    local diff_busy=$((busy2 - busy1))

    [[ $diff_total -gt 0 ]] && echo $((diff_busy * 100 / diff_total)) || echo "0"
}

# Print a line with fixed width (68 chars inside borders)
W=68

line() {
    local color=$1
    local content=$2
    # Pad or truncate to exactly W characters
    printf "${color}│${NC} %-${W}s ${color}│${NC}\n" "$content"
}

header_line() {
    local color=$1
    local title=$2
    local dashes=""
    local title_len=${#title}
    local remaining=$((W - title_len - 2))
    for ((i=0; i<remaining; i++)); do dashes+="─"; done
    echo -e "${color}${BOLD}┌─ ${title} ${dashes}┐${NC}"
}

footer_line() {
    local color=$1
    local dashes=""
    for ((i=0; i<W+2; i++)); do dashes+="─"; done
    echo -e "${color}└${dashes}┘${NC}"
}

sep_line() {
    local color=$1
    local dashes=""
    for ((i=0; i<W+2; i++)); do dashes+="─"; done
    echo -e "${color}├${dashes}┤${NC}"
}

# Main display function
display_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Title
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    printf "${BOLD}║%70s║${NC}\n" "AMD Strix Halo System Status - $timestamp  "
    echo -e "${BOLD}╚══════════════════════════════════════════════════════════════════════╝${NC}"
    echo

    # GPU Section
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
    local mem_busy=$(cat "$GPU_PATH/mem_busy_percent" 2>/dev/null || echo "0")
    local gpu_bar=$(progress_bar "$gpu_busy" 20)

    local util_color=$GREEN
    [[ "$gpu_busy" -ge 80 ]] && util_color=$RED
    [[ "$gpu_busy" -ge 50 ]] && [[ "$gpu_busy" -lt 80 ]] && util_color=$YELLOW

    local temp_color=$GREEN
    (( $(echo "$gpu_temp > 80" | bc -l 2>/dev/null || echo 0) )) && temp_color=$RED
    (( $(echo "$gpu_temp > 70" | bc -l 2>/dev/null || echo 0) )) && (( $(echo "$gpu_temp <= 80" | bc -l 2>/dev/null || echo 0) )) && temp_color=$YELLOW

    header_line "$CYAN" "GPU (Radeon 8060S)"
    printf "${CYAN}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${CYAN}│${NC}\n" "Clock:" "$gpu_clock" "Fabric Clock:" "$gpu_fclk"
    printf "${CYAN}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${CYAN}│${NC}\n" "SOC Clock:" "$gpu_socclk" "Memory Clock:" "$gpu_mclk"
    printf "${CYAN}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${CYAN}│${NC}\n" "Perf Level:" "$gpu_perf" "Mem Bandwidth:" "${mem_busy}%"
    printf "${CYAN}│${NC} %-16s ${util_color}%-5s ${util_color}%-20s${NC} %19s ${CYAN}│${NC}\n" "Utilization:" "${gpu_busy}%" "$gpu_bar" ""
    printf "${CYAN}│${NC} %-16s ${temp_color}%-14s${NC} %-18s ${YELLOW}%-14s${NC} ${CYAN}│${NC}\n" "Temperature:" "${gpu_temp}°C" "Power:" "${gpu_power}W"
    footer_line "$CYAN"
    echo

    # CPU Section
    local cpu_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    local cpu_freq_sum=0
    local cpu_count=0
    for freq_file in /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq; do
        [[ -f "$freq_file" ]] && { freq=$(cat "$freq_file" 2>/dev/null || echo "0"); cpu_freq_sum=$((cpu_freq_sum + freq)); cpu_count=$((cpu_count + 1)); }
    done
    local cpu_freq=$((cpu_freq_sum / cpu_count / 1000))
    local cpu_temp_mc=$(cat /sys/class/hwmon/hwmon3/temp1_input 2>/dev/null || echo "0")
    local cpu_temp=$(awk "BEGIN {printf \"%.1f\", $cpu_temp_mc / 1000}")
    local cpu_util=$(get_cpu_utilization)
    local cpu_bar=$(progress_bar "$cpu_util" 20)

    local cpu_util_color=$GREEN
    [[ "$cpu_util" -ge 80 ]] && cpu_util_color=$RED
    [[ "$cpu_util" -ge 50 ]] && [[ "$cpu_util" -lt 80 ]] && cpu_util_color=$YELLOW

    local cpu_temp_color=$GREEN
    (( $(echo "$cpu_temp > 90" | bc -l 2>/dev/null || echo 0) )) && cpu_temp_color=$RED
    (( $(echo "$cpu_temp > 80" | bc -l 2>/dev/null || echo 0) )) && (( $(echo "$cpu_temp <= 90" | bc -l 2>/dev/null || echo 0) )) && cpu_temp_color=$YELLOW

    header_line "$BLUE" "CPU (Ryzen AI MAX+ 395)"
    printf "${BLUE}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${BLUE}│${NC}\n" "Governor:" "$cpu_gov" "Avg Frequency:" "${cpu_freq}MHz"
    printf "${BLUE}│${NC} %-16s ${cpu_util_color}%-5s ${cpu_util_color}%-20s${NC} %19s ${BLUE}│${NC}\n" "Utilization:" "${cpu_util}%" "$cpu_bar" ""
    printf "${BLUE}│${NC} %-16s ${cpu_temp_color}%-14s${NC} %34s ${BLUE}│${NC}\n" "Temperature:" "${cpu_temp}°C" ""
    footer_line "$BLUE"
    echo

    # Memory Section
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    local mem_used=$(free -g | awk '/^Mem:/{print $3}')
    local mem_percent=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
    local vram_total=$(($(cat "$GPU_PATH/mem_info_vram_total" 2>/dev/null || echo 0) / 1024 / 1024))
    local vram_used=$(($(cat "$GPU_PATH/mem_info_vram_used" 2>/dev/null || echo 0) / 1024 / 1024))
    local gtt_total=$(($(cat "$GPU_PATH/mem_info_gtt_total" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
    local gtt_used=$(($(cat "$GPU_PATH/mem_info_gtt_used" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))

    header_line "$YELLOW" "Memory"
    printf "${YELLOW}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${YELLOW}│${NC}\n" "System RAM:" "${mem_used}G / ${mem_total}G" "Usage:" "${mem_percent}%"
    printf "${YELLOW}│${NC} %-16s ${GREEN}%-14s${NC} %-18s ${GREEN}%-14s${NC} ${YELLOW}│${NC}\n" "VRAM:" "${vram_used}M / ${vram_total}M" "GTT:" "${gtt_used}G / ${gtt_total}G"
    footer_line "$YELLOW"
    echo

    # Running Models Section
    header_line "$GREEN" "Running Models"
    printf "${GREEN}│${NC} ${BOLD}%-17s %5s %6s %5s %5s %11s${NC}  ${GREEN}│${NC}\n" "Model" "Port" "Ctx" "CPU%" "MEM%" "Runtime"
    sep_line "$GREEN"

    local model_count=0
    local models_data=""
    while IFS='|' read -r model port ctx cpu mem pid runtime; do
        if [[ -n "$model" ]]; then
            printf "${GREEN}│${NC} %-17s %5s %6s %5s %5s %11s  ${GREEN}│${NC}\n" "$model" "$port" "$ctx" "$cpu" "$mem" "$runtime"
            models_data+="$model|$port|$ctx|$cpu|$mem|$pid|$runtime"$'\n'
            model_count=$((model_count + 1))
        fi
    done <<< "$(get_running_models)"

    [[ $model_count -eq 0 ]] && printf "${GREEN}│${NC} %-68s ${GREEN}│${NC}\n" "No models currently running"
    footer_line "$GREEN"
    echo

    # Token Statistics Section
    if [[ $model_count -gt 0 ]]; then
        header_line "$CYAN" "Token Statistics"
        printf "${CYAN}│${NC} ${BOLD}%-17s %8s %8s %10s %10s${NC}   ${CYAN}│${NC}\n" "Model" "In Tok" "Out Tok" "In tok/s" "Out tok/s"
        sep_line "$CYAN"

        local has_metrics=false
        while IFS='|' read -r model port ctx cpu mem pid runtime; do
            if [[ -n "$model" ]] && [[ "$port" != "?" ]]; then
                IFS='|' read -r prompt_tok gen_tok prompt_sec gen_sec <<< "$(get_model_metrics "$port")"

                if [[ "$prompt_tok" != "N/A" ]]; then
                    has_metrics=true
                    IFS='|' read -r in_tps out_tps <<< "$(get_instantaneous_tps "$model" "$prompt_tok" "$gen_tok")"

                    local fmt_prompt=$(format_number "$prompt_tok")
                    local fmt_gen=$(format_number "$gen_tok")

                    local in_color=$NC
                    local out_color=$NC
                    [[ "$in_tps" != "--" ]] && [[ "$in_tps" != "0.0" ]] && in_color=$GREEN
                    [[ "$out_tps" != "--" ]] && [[ "$out_tps" != "0.0" ]] && out_color=$GREEN

                    printf "${CYAN}│${NC} %-17s %8s %8s ${in_color}%10s${NC} ${out_color}%10s${NC}   ${CYAN}│${NC}\n" "$model" "$fmt_prompt" "$fmt_gen" "$in_tps" "$out_tps"
                else
                    printf "${CYAN}│${NC} %-17s ${YELLOW}%-50s${NC} ${CYAN}│${NC}\n" "$model" "(metrics not enabled)"
                fi
            fi
        done <<< "$models_data"

        footer_line "$CYAN"
    fi

    if $WATCH_MODE; then
        echo
        echo -e "${DIM}Refreshing every ${INTERVAL}s. Press Ctrl+C to exit.${NC}"
    fi
}

# Main execution
if $WATCH_MODE; then
    tput civis
    clear
    trap 'tput cnorm; echo -e "\n${GREEN}Exiting...${NC}"; exit 0' INT TERM
    while true; do
        tput cup 0 0
        display_status
        tput ed
        sleep "$INTERVAL"
    done
else
    display_status
fi
