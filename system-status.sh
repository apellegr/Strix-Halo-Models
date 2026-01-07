#!/bin/bash
# system-status.sh - Monitor AMD Strix Halo system status
# Shows GPU/CPU config, temperatures, power, and running models

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# Settings
WATCH_MODE=false
INTERVAL=1
SHOW_HELP=false

# State directory for metrics tracking
STATE_DIR="/tmp/system-status-metrics"
mkdir -p "$STATE_DIR"

cleanup() {
    if ! $WATCH_MODE; then
        find "$STATE_DIR" -type f -mmin +1 -delete 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -w|--watch) WATCH_MODE=true; shift ;;
        -i|--interval) INTERVAL="$2"; shift 2 ;;
        -h|--help) SHOW_HELP=true; shift ;;
        *) echo "Unknown option: $1"; exit 1 ;;
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
    exit 0
fi

# Paths
GPU_PATH="/sys/class/drm/card0/device"
GPU_HWMON="/sys/class/drm/card0/device/hwmon/hwmon5"

# Helper functions
read_dpm_clock() {
    grep '\*' "$1" 2>/dev/null | awk '{print $2}' | head -1
}

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

get_model_metrics() {
    local port=$1
    local metrics=$(curl -s --max-time 3 "http://localhost:$port/metrics" 2>/dev/null)
    if [[ -z "$metrics" ]] || echo "$metrics" | grep -q '"error"'; then
        echo "N/A|N/A|N/A|N/A"
        return
    fi
    local prompt_tokens=$(echo "$metrics" | grep '^llamacpp:prompt_tokens_total' | awk '{print $2}' | head -1)
    local gen_tokens=$(echo "$metrics" | grep '^llamacpp:tokens_predicted_total' | awk '{print $2}' | head -1)
    echo "${prompt_tokens:-0}|${gen_tokens:-0}|0|0"
}

get_instantaneous_tps() {
    local model=$1 prompt_tok=$2 gen_tok=$3
    local current_time=$(date +%s.%N)
    local state_file="$STATE_DIR/${model}.state"
    local in_tps="--" out_tps="--"

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

progress_bar() {
    local percent=$1 width=${2:-20}
    [[ -z "$percent" ]] || ! [[ "$percent" =~ ^[0-9]+$ ]] && percent=0
    local filled=$((percent * width / 100))
    local empty=$((width - filled))
    local bar=""
    for ((i=0; i<filled; i++)); do bar+="█"; done
    for ((i=0; i<empty; i++)); do bar+="░"; done
    echo "$bar"
}

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

# Table width (content between borders)
W=70

# Print functions - build strings to exact width, then add borders
print_header() {
    local color=$1 title=$2
    local title_part="─ ${title} "
    local title_len=$((${#title} + 3))
    local dashes=$((W - title_len))
    local line="┌${title_part}"
    for ((i=0; i<dashes; i++)); do line+="─"; done
    line+="┐"
    echo -e "${color}${BOLD}${line}${NC}"
}

print_footer() {
    local color=$1
    local line="└"
    for ((i=0; i<W; i++)); do line+="─"; done
    line+="┘"
    echo -e "${color}${line}${NC}"
}

print_sep() {
    local color=$1
    local line="├"
    for ((i=0; i<W; i++)); do line+="─"; done
    line+="┤"
    echo -e "${color}${line}${NC}"
}

# Pad string to exact width (plain text, no colors)
pad() {
    local str="$1" width=$2
    local len=${#str}
    if [[ $len -ge $width ]]; then
        echo "${str:0:$width}"
    else
        local spaces=$((width - len))
        local padding=""
        for ((i=0; i<spaces; i++)); do padding+=" "; done
        echo "${str}${padding}"
    fi
}

# Print a row - auto-pads content to exactly W characters
print_row() {
    local color=$1
    shift
    local content="$*"
    # Strip ANSI codes to measure visible length
    local visible=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local len=${#visible}
    local padding=""
    if [[ $len -lt $W ]]; then
        local need=$((W - len))
        for ((i=0; i<need; i++)); do padding+=" "; done
    fi
    echo -e "${color}│${NC}${content}${padding}${color}│${NC}"
}

display_status() {
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

    # Title box
    echo -e "${BOLD}╔══════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BOLD}║           AMD Strix Halo System Status - ${timestamp}           ║${NC}"
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

    print_header "$CYAN" "GPU (Radeon 8060S)"
    print_row "$CYAN" " $(pad "Clock:" 16)${GREEN}$(pad "$gpu_clock" 12)${NC}  $(pad "Fabric Clock:" 16)${GREEN}$(pad "$gpu_fclk" 12)${NC}  "
    print_row "$CYAN" " $(pad "SOC Clock:" 16)${GREEN}$(pad "$gpu_socclk" 12)${NC}  $(pad "Memory Clock:" 16)${GREEN}$(pad "$gpu_mclk" 12)${NC}  "
    print_row "$CYAN" " $(pad "Perf Level:" 16)${GREEN}$(pad "$gpu_perf" 12)${NC}  $(pad "Mem Bandwidth:" 16)${GREEN}$(pad "${mem_busy}%" 12)${NC}  "
    print_row "$CYAN" " $(pad "Utilization:" 16)${util_color}$(pad "${gpu_busy}%" 6)${gpu_bar}${NC}$(pad "" 16)  "
    print_row "$CYAN" " $(pad "Temperature:" 16)${temp_color}$(pad "${gpu_temp}°C" 12)${NC}  $(pad "Power:" 16)${YELLOW}$(pad "${gpu_power}W" 12)${NC}  "
    print_footer "$CYAN"
    echo

    # CPU Section
    local cpu_gov=$(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>/dev/null)
    local cpu_freq_sum=0 cpu_count=0
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

    print_header "$BLUE" "CPU (Ryzen AI MAX+ 395)"
    print_row "$BLUE" " $(pad "Governor:" 16)${GREEN}$(pad "$cpu_gov" 12)${NC}  $(pad "Avg Frequency:" 16)${GREEN}$(pad "${cpu_freq}MHz" 12)${NC}  "
    print_row "$BLUE" " $(pad "Utilization:" 16)${cpu_util_color}$(pad "${cpu_util}%" 6)${cpu_bar}${NC}$(pad "" 16)  "
    print_row "$BLUE" " $(pad "Temperature:" 16)${cpu_temp_color}$(pad "${cpu_temp}°C" 12)${NC}  $(pad "" 16)$(pad "" 14)  "
    print_footer "$BLUE"
    echo

    # Memory Section
    local mem_total=$(free -g | awk '/^Mem:/{print $2}')
    local mem_used=$(free -g | awk '/^Mem:/{print $3}')
    local mem_percent=$(free | awk '/^Mem:/{printf "%.0f", $3/$2 * 100}')
    local vram_total=$(($(cat "$GPU_PATH/mem_info_vram_total" 2>/dev/null || echo 0) / 1024 / 1024))
    local vram_used=$(($(cat "$GPU_PATH/mem_info_vram_used" 2>/dev/null || echo 0) / 1024 / 1024))
    local gtt_total=$(($(cat "$GPU_PATH/mem_info_gtt_total" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))
    local gtt_used=$(($(cat "$GPU_PATH/mem_info_gtt_used" 2>/dev/null || echo 0) / 1024 / 1024 / 1024))

    print_header "$YELLOW" "Memory"
    print_row "$YELLOW" " $(pad "System RAM:" 16)${GREEN}$(pad "${mem_used}G / ${mem_total}G" 12)${NC}  $(pad "Usage:" 16)${GREEN}$(pad "${mem_percent}%" 12)${NC}  "
    print_row "$YELLOW" " $(pad "VRAM:" 16)${GREEN}$(pad "${vram_used}M / ${vram_total}M" 12)${NC}  $(pad "GTT:" 16)${GREEN}$(pad "${gtt_used}G / ${gtt_total}G" 12)${NC}  "
    print_footer "$YELLOW"
    echo

    # Running Models Section
    print_header "$GREEN" "Running Models"
    print_row "$GREEN" " ${BOLD}$(pad "Model" 18)$(pad "Port" 7)$(pad "Ctx" 7)$(pad "CPU%" 6)$(pad "MEM%" 6)$(pad "Runtime" 12)${NC} "
    print_sep "$GREEN"

    local model_count=0
    local models_data=""
    while IFS='|' read -r model port ctx cpu mem pid runtime; do
        if [[ -n "$model" ]]; then
            print_row "$GREEN" " $(pad "$model" 18)$(pad "$port" 7)$(pad "$ctx" 7)$(pad "$cpu" 6)$(pad "$mem" 6)$(pad "$runtime" 12) "
            models_data+="$model|$port|$ctx|$cpu|$mem|$pid|$runtime"$'\n'
            model_count=$((model_count + 1))
        fi
    done <<< "$(get_running_models)"

    [[ $model_count -eq 0 ]] && print_row "$GREEN" " $(pad "No models currently running" 68) "
    print_footer "$GREEN"
    echo

    # Token Statistics Section
    if [[ $model_count -gt 0 ]]; then
        print_header "$CYAN" "Token Statistics"
        print_row "$CYAN" " ${BOLD}$(pad "Model" 18)$(pad "In Tok" 10)$(pad "Out Tok" 10)$(pad "In tok/s" 12)$(pad "Out tok/s" 12)${NC} "
        print_sep "$CYAN"

        while IFS='|' read -r model port ctx cpu mem pid runtime; do
            if [[ -n "$model" ]] && [[ "$port" != "?" ]]; then
                IFS='|' read -r prompt_tok gen_tok prompt_sec gen_sec <<< "$(get_model_metrics "$port")"
                if [[ "$prompt_tok" != "N/A" ]]; then
                    IFS='|' read -r in_tps out_tps <<< "$(get_instantaneous_tps "$model" "$prompt_tok" "$gen_tok")"
                    local fmt_prompt=$(format_number "$prompt_tok")
                    local fmt_gen=$(format_number "$gen_tok")
                    local in_color=$NC out_color=$NC
                    [[ "$in_tps" != "--" ]] && [[ "$in_tps" != "0.0" ]] && in_color=$GREEN
                    [[ "$out_tps" != "--" ]] && [[ "$out_tps" != "0.0" ]] && out_color=$GREEN
                    print_row "$CYAN" " $(pad "$model" 18)$(pad "$fmt_prompt" 10)$(pad "$fmt_gen" 10)${in_color}$(pad "$in_tps" 12)${NC}${out_color}$(pad "$out_tps" 12)${NC} "
                else
                    print_row "$CYAN" " $(pad "$model" 18)${DIM}$(pad "(server busy)" 44)${NC} "
                fi
            fi
        done <<< "$models_data"

        print_footer "$CYAN"
    fi

    if $WATCH_MODE; then
        echo
        echo -e "${DIM}Refreshing every ${INTERVAL}s. Press Ctrl+C to exit.${NC}"
    fi
}

# Main
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
