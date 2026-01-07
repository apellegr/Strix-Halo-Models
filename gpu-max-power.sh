#!/bin/bash
# gpu-max-power.sh - Maximize GPU power on AMD Strix Halo
# Tested on: AMD Ryzen AI MAX+ 395 with Radeon 8060S

set -e

echo "=== AMD Strix Halo GPU Power Configuration ==="
echo ""

# Force high performance level
echo "[1/3] Setting GPU performance level to 'high'..."
echo "high" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level > /dev/null

# Set power limits (140W package, 120W APU)
echo "[2/3] Setting power limits (STAPM=140W, PPT=140W, APU=120W)..."
sudo ryzenadj --stapm-limit=140000 --fast-limit=140000 --slow-limit=140000 --apu-slow-limit=120000 2>&1 | grep -E "^(CPU|SMU)" || true

# Set CPU to powersave to give GPU more headroom
echo "[3/3] Setting CPU governor to 'powersave'..."
echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor > /dev/null

echo ""
echo "=== Configuration Applied ==="
echo ""
echo "GPU Performance Level: $(cat /sys/class/drm/card0/device/power_dpm_force_performance_level)"
echo "CPU Governor: $(cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor)"
echo "GPU Clock: $(cat /sys/class/drm/card0/device/pp_dpm_sclk | grep '\*' | awk '{print $2}')"
echo "FCLK: $(cat /sys/class/drm/card0/device/pp_dpm_fclk | grep '\*' | awk '{print $2}')"
echo ""
echo "Run 'sudo ryzenadj -i' for detailed power limits."
