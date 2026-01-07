# AMD Strix Halo GPU Power Configuration

Configuration guide for maximizing GPU power and performance on AMD Ryzen AI MAX+ 395 with Radeon 8060S.

## System Information

| Component | Value |
|-----------|-------|
| CPU | AMD Ryzen AI MAX+ 395 (16 cores / 32 threads) |
| GPU | AMD Radeon 8060S (Device 1586) |
| Max GPU Clock | 2900 MHz |
| Max FCLK | 2000 MHz |
| Max SOCCLK | 1472 MHz |

## Prerequisites

### Install RyzenAdj

RyzenAdj is required to modify APU power limits.

```bash
# Install dependencies
sudo apt install -y libpci-dev build-essential cmake git

# Clone and build
cd /tmp
git clone https://github.com/FlyGoat/RyzenAdj.git
cd RyzenAdj
mkdir build && cd build
cmake ..
make -j$(nproc)
sudo make install
```

## Power Configuration Commands

### 1. Force GPU to Maximum Performance Level

Prevents GPU clocks from downclocking:

```bash
echo "high" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
```

### 2. Set Maximum Package Power Limits

Increase STAPM, PPT fast/slow limits to 140W and APU limit to 120W:

```bash
sudo ryzenadj --stapm-limit=140000 --fast-limit=140000 --slow-limit=140000 --apu-slow-limit=120000
```

### 3. Reduce CPU Power for GPU Headroom

Switch CPU governor to powersave (allows CPU to downclock, freeing power for GPU):

```bash
echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

Alternative: Cap CPU frequency (e.g., to 3.0 GHz):

```bash
echo 3000000 | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_max_freq
```

## All-in-One Script

Create and run this script to apply all settings:

```bash
#!/bin/bash
# gpu-max-power.sh - Maximize GPU power on Strix Halo

set -e

echo "Applying GPU maximum power configuration..."

# Force high performance level
echo "high" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level

# Set power limits (140W package, 120W APU)
sudo ryzenadj --stapm-limit=140000 --fast-limit=140000 --slow-limit=140000 --apu-slow-limit=120000

# Set CPU to powersave to give GPU more headroom
echo "powersave" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor

echo "Configuration applied!"
echo ""
echo "Verifying settings..."
sudo ryzenadj -i | grep -E "LIMIT|VALUE"
cat /sys/class/drm/card0/device/power_dpm_force_performance_level
cat /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor
```

## Monitoring Commands

### View Current Power Limits

```bash
sudo ryzenadj -i
```

### Check GPU Clock States

```bash
cat /sys/class/drm/card0/device/pp_dpm_sclk    # GPU shader clock
cat /sys/class/drm/card0/device/pp_dpm_fclk    # Fabric clock
cat /sys/class/drm/card0/device/pp_dpm_socclk  # SOC clock
cat /sys/class/drm/card0/device/pp_dpm_mclk    # Memory clock
```

### Check GPU Power and Utilization

```bash
# Current power (in microwatts, divide by 1000000 for watts)
cat /sys/class/drm/card0/device/hwmon/hwmon5/power1_average

# GPU utilization percentage
cat /sys/class/drm/card0/device/gpu_busy_percent

# Current GPU frequency (in Hz)
cat /sys/class/drm/card0/device/hwmon/hwmon5/freq1_input
```

### Check CPU Governor

```bash
cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor | sort | uniq -c
```

## Reset to Default Settings

### Reset GPU Performance Level

```bash
echo "auto" | sudo tee /sys/class/drm/card0/device/power_dpm_force_performance_level
```

### Reset CPU Governor to Performance

```bash
echo "performance" | sudo tee /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor
```

### Reset Power Limits (reboot or use default values)

```bash
# Default Strix Halo values (may vary by SKU)
sudo ryzenadj --stapm-limit=120000 --fast-limit=140000 --slow-limit=120000 --apu-slow-limit=70000
```

## Expected Results After Configuration

| Setting | Before | After |
|---------|--------|-------|
| Performance Level | auto | high |
| GPU Clock (SCLK) | 2900 MHz | 2900 MHz (locked) |
| SOC Clock | variable | 1472 MHz (max) |
| Fabric Clock (FCLK) | variable | 2000 MHz (max) |
| STAPM Limit | 120W | 140W |
| PPT Fast Limit | 140W | 140W |
| PPT Slow Limit | 120W | 140W |
| APU Power Limit | 70W | 120W |
| CPU Governor | performance | powersave |

## Notes

- These settings do not persist across reboots. Add to a startup script or systemd service if needed.
- Monitor temperatures (`/sys/class/drm/card0/device/hwmon/hwmon5/temp1_input`) to ensure adequate cooling.
- Power limits may be constrained by BIOS settings on some systems.
- The `ryzenadj` tool uses `/dev/mem` fallback if no `ryzen_smu` kernel module is loaded.

## Kernel Boot Parameters

Current relevant boot parameter:
```
amdgpu.gttsize=117760
```

This sets the GTT (Graphics Translation Table) size to ~115GB, allowing the GPU to access system RAM.
