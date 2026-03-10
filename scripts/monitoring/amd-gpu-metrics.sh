#!/bin/bash
# AMD GPU Metrics Collector for Prometheus Node Exporter Textfile Collector
# Writes metrics to a .prom file that node_exporter can read
#
# Usage:
#   ./amd-gpu-metrics.sh > /var/lib/node_exporter/textfile_collector/amd_gpu.prom
#
# Run via cron every 15 seconds or via systemd timer

set -e

GPU_PATH="/sys/class/drm/card0/device"
HWMON_PATH=$(ls -d ${GPU_PATH}/hwmon/hwmon* 2>/dev/null | head -1)

# Helper function to safely read a sysfs file
read_metric() {
    local file="$1"
    if [ -f "$file" ] && [ -r "$file" ]; then
        cat "$file" 2>/dev/null || echo ""
    fi
}

# GPU Utilization (0-100%)
gpu_busy=$(read_metric "${GPU_PATH}/gpu_busy_percent")
if [ -n "$gpu_busy" ]; then
    echo "# HELP amd_gpu_busy_percent GPU utilization percentage"
    echo "# TYPE amd_gpu_busy_percent gauge"
    echo "amd_gpu_busy_percent $gpu_busy"
fi

# VRAM Total (bytes)
vram_total=$(read_metric "${GPU_PATH}/mem_info_vram_total")
if [ -n "$vram_total" ]; then
    echo "# HELP amd_gpu_vram_total_bytes Total VRAM in bytes"
    echo "# TYPE amd_gpu_vram_total_bytes gauge"
    echo "amd_gpu_vram_total_bytes $vram_total"
fi

# VRAM Used (bytes)
vram_used=$(read_metric "${GPU_PATH}/mem_info_vram_used")
if [ -n "$vram_used" ]; then
    echo "# HELP amd_gpu_vram_used_bytes Used VRAM in bytes"
    echo "# TYPE amd_gpu_vram_used_bytes gauge"
    echo "amd_gpu_vram_used_bytes $vram_used"
fi

# GTT Total (system memory for GPU, bytes)
gtt_total=$(read_metric "${GPU_PATH}/mem_info_gtt_total")
if [ -n "$gtt_total" ]; then
    echo "# HELP amd_gpu_gtt_total_bytes Total GTT memory in bytes"
    echo "# TYPE amd_gpu_gtt_total_bytes gauge"
    echo "amd_gpu_gtt_total_bytes $gtt_total"
fi

# GTT Used (bytes)
gtt_used=$(read_metric "${GPU_PATH}/mem_info_gtt_used")
if [ -n "$gtt_used" ]; then
    echo "# HELP amd_gpu_gtt_used_bytes Used GTT memory in bytes"
    echo "# TYPE amd_gpu_gtt_used_bytes gauge"
    echo "amd_gpu_gtt_used_bytes $gtt_used"
fi

# Temperature (convert from millidegrees to degrees)
if [ -n "$HWMON_PATH" ]; then
    temp_raw=$(read_metric "${HWMON_PATH}/temp1_input")
    if [ -n "$temp_raw" ]; then
        temp_celsius=$(echo "scale=2; $temp_raw / 1000" | bc)
        echo "# HELP amd_gpu_temperature_celsius GPU temperature in Celsius"
        echo "# TYPE amd_gpu_temperature_celsius gauge"
        echo "amd_gpu_temperature_celsius $temp_celsius"
    fi

    # Power (convert from microwatts to watts)
    power_raw=$(read_metric "${HWMON_PATH}/power1_average")
    if [ -n "$power_raw" ]; then
        power_watts=$(echo "scale=2; $power_raw / 1000000" | bc)
        echo "# HELP amd_gpu_power_watts GPU power consumption in watts"
        echo "# TYPE amd_gpu_power_watts gauge"
        echo "amd_gpu_power_watts $power_watts"
    fi
fi
