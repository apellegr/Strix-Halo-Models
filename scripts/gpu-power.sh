#!/bin/bash
# gpu-power.sh - Control AMD Strix Halo GPU power/performance
# Controls power indirectly through clock limits and performance profiles

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# Auto-detect GPU
GPU_CARD=""
for card in /sys/class/drm/card*/device/gpu_busy_percent; do
    if [[ -f "$card" ]]; then
        GPU_CARD=$(dirname "$card")
        break
    fi
done
[[ -z "$GPU_CARD" ]] && { echo -e "${RED}Error: No AMD GPU found${NC}"; exit 1; }

GPU_HWMON=$(ls -d "$GPU_CARD"/hwmon/hwmon* 2>/dev/null | head -1)

# Get current values
get_status() {
    local perf_level=$(cat "$GPU_CARD/power_dpm_force_performance_level" 2>/dev/null)
    local current_sclk=$(grep '\*' "$GPU_CARD/pp_dpm_sclk" 2>/dev/null | awk '{print $2}')
    local power_uw=$(cat "$GPU_HWMON/power1_average" 2>/dev/null || echo "0")
    local power_w=$(awk "BEGIN {printf \"%.1f\", $power_uw / 1000000}")
    local gpu_busy=$(cat "$GPU_CARD/gpu_busy_percent" 2>/dev/null || echo "0")
    local temp_mc=$(cat "$GPU_HWMON/temp1_input" 2>/dev/null || echo "0")
    local temp_c=$(awk "BEGIN {printf \"%.1f\", $temp_mc / 1000}")

    # Get clock range from OD table (filter null bytes first)
    local od_data=$(tr -d '\0' < "$GPU_CARD/pp_od_clk_voltage" 2>/dev/null)
    local min_sclk=$(echo "$od_data" | grep "^SCLK:" | awk '{print $2}' | tr -d 'Mhz')
    local max_sclk=$(echo "$od_data" | grep "^SCLK:" | awk '{print $3}' | tr -d 'Mhz')

    # Get current OD setting
    local od_max=$(echo "$od_data" | awk '/^1:/{print $2}' | tr -d 'Mhz')

    echo -e "${BOLD}GPU Power Status${NC}"
    echo -e "────────────────────────────────────"
    echo -e "Performance Level:  ${GREEN}$perf_level${NC}"
    echo -e "Current Clock:      ${GREEN}$current_sclk${NC}"
    echo -e "Max Clock (OD):     ${GREEN}${od_max}Mhz${NC}"
    echo -e "Clock Range:        ${CYAN}${min_sclk}-${max_sclk}Mhz${NC}"
    echo -e "Power Draw:         ${YELLOW}${power_w}W${NC}"
    echo -e "GPU Utilization:    ${GREEN}${gpu_busy}%${NC}"
    echo -e "Temperature:        ${GREEN}${temp_c}°C${NC}"
}

# Set performance level
set_perf_level() {
    local level=$1
    local valid_levels="auto low high manual profile_standard profile_min_sclk profile_min_mclk profile_peak"

    if ! echo "$valid_levels" | grep -qw "$level"; then
        echo -e "${RED}Invalid level: $level${NC}"
        echo -e "Valid options: $valid_levels"
        exit 1
    fi

    echo -e "Setting performance level to ${GREEN}$level${NC}..."
    echo "$level" | sudo tee "$GPU_CARD/power_dpm_force_performance_level" > /dev/null
    echo -e "${GREEN}Done${NC}"
}

# Set max GPU clock (requires manual mode)
set_max_clock() {
    local clock=$1

    # Validate clock value (filter null bytes)
    local od_data=$(tr -d '\0' < "$GPU_CARD/pp_od_clk_voltage" 2>/dev/null)
    local min_sclk=$(echo "$od_data" | grep "^SCLK:" | awk '{print $2}' | tr -d 'Mhz')
    local max_sclk=$(echo "$od_data" | grep "^SCLK:" | awk '{print $3}' | tr -d 'Mhz')

    if [[ $clock -lt $min_sclk ]] || [[ $clock -gt $max_sclk ]]; then
        echo -e "${RED}Clock must be between ${min_sclk}Mhz and ${max_sclk}Mhz${NC}"
        exit 1
    fi

    echo -e "Setting max GPU clock to ${GREEN}${clock}Mhz${NC}..."

    # Set to manual mode first
    echo "manual" | sudo tee "$GPU_CARD/power_dpm_force_performance_level" > /dev/null

    # Set the overdrive clock
    echo "s 1 $clock" | sudo tee "$GPU_CARD/pp_od_clk_voltage" > /dev/null
    echo "c" | sudo tee "$GPU_CARD/pp_od_clk_voltage" > /dev/null

    echo -e "${GREEN}Done${NC}"
}

# Reset to defaults
reset_defaults() {
    echo -e "Resetting GPU to defaults..."
    echo "r" | sudo tee "$GPU_CARD/pp_od_clk_voltage" > /dev/null 2>&1 || true
    echo "c" | sudo tee "$GPU_CARD/pp_od_clk_voltage" > /dev/null 2>&1 || true
    echo "auto" | sudo tee "$GPU_CARD/power_dpm_force_performance_level" > /dev/null
    echo -e "${GREEN}Done - GPU reset to auto mode${NC}"
}

# Presets
apply_preset() {
    local preset=$1
    case $preset in
        low|powersave)
            echo -e "${CYAN}Applying low power preset...${NC}"
            set_max_clock 1200
            ;;
        balanced)
            echo -e "${CYAN}Applying balanced preset...${NC}"
            set_max_clock 2000
            ;;
        performance|high)
            echo -e "${CYAN}Applying performance preset...${NC}"
            set_max_clock 2900
            ;;
        *)
            echo -e "${RED}Unknown preset: $preset${NC}"
            echo "Available presets: low, balanced, performance"
            exit 1
            ;;
    esac
}

# Usage
usage() {
    echo -e "${BOLD}gpu-power.sh${NC} - Control AMD GPU power/performance"
    echo
    echo -e "${BOLD}Usage:${NC}"
    echo "  $0                     Show current status"
    echo "  $0 status              Show current status"
    echo "  $0 level <LEVEL>       Set performance level"
    echo "  $0 clock <MHZ>         Set max GPU clock (600-2900)"
    echo "  $0 preset <PRESET>     Apply a preset"
    echo "  $0 reset               Reset to defaults"
    echo
    echo -e "${BOLD}Performance Levels:${NC}"
    echo "  auto                   Let driver manage (default)"
    echo "  low                    Force lowest power state"
    echo "  high                   Force highest power state"
    echo "  manual                 Required for custom clock"
    echo "  profile_min_sclk       Minimize GPU clock"
    echo "  profile_peak           Maximum performance"
    echo
    echo -e "${BOLD}Presets:${NC}"
    echo "  low/powersave          Max 1200Mhz (~30-40W)"
    echo "  balanced               Max 2000Mhz (~50-60W)"
    echo "  performance/high       Max 2900Mhz (~80-100W)"
    echo
    echo -e "${BOLD}Examples:${NC}"
    echo "  $0 preset low          Apply low power mode"
    echo "  $0 clock 1800          Set max clock to 1800Mhz"
    echo "  $0 level auto          Return to automatic mode"
}

# Main
case "${1:-status}" in
    status|"")
        get_status
        ;;
    level)
        [[ -z "$2" ]] && { echo -e "${RED}Error: Specify a level${NC}"; usage; exit 1; }
        set_perf_level "$2"
        get_status
        ;;
    clock)
        [[ -z "$2" ]] && { echo -e "${RED}Error: Specify clock in Mhz${NC}"; usage; exit 1; }
        set_max_clock "$2"
        get_status
        ;;
    preset)
        [[ -z "$2" ]] && { echo -e "${RED}Error: Specify a preset${NC}"; usage; exit 1; }
        apply_preset "$2"
        get_status
        ;;
    reset)
        reset_defaults
        get_status
        ;;
    -h|--help|help)
        usage
        ;;
    *)
        echo -e "${RED}Unknown command: $1${NC}"
        usage
        exit 1
        ;;
esac
