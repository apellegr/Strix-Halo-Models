#!/bin/bash
# GPU Memory Verification Script for ROCm Investigation
# Run after reboot to check if kernel parameters took effect

echo "=== System Memory ==="
free -h | grep Mem

echo -e "\n=== Kernel Boot Parameters ==="
cat /proc/cmdline

echo -e "\n=== TTM Parameters ==="
echo "pages_limit: $(cat /sys/module/ttm/parameters/pages_limit) pages"
awk -v p=$(cat /sys/module/ttm/parameters/pages_limit) 'BEGIN{printf "            = %.2f GB\n", p*4/1024/1024}'

echo -e "\n=== Kernel GPU Memory Info ==="
echo "GTT Total:  $(awk '{printf "%.2f GB", $1/1024/1024/1024}' /sys/class/drm/card0/device/mem_info_gtt_total)"
echo "VRAM Total: $(awk '{printf "%.2f GB", $1/1024/1024/1024}' /sys/class/drm/card0/device/mem_info_vram_total)"

echo -e "\n=== KFD Node Properties ==="
echo "local_mem_size: $(grep local_mem_size /sys/class/kfd/kfd/topology/nodes/1/properties)"

echo -e "\n=== KFD Memory Bank ==="
cat /sys/class/kfd/kfd/topology/nodes/1/mem_banks/0/properties

echo -e "\n=== ROCm SMI Memory ==="
rocm-smi --showmeminfo vram gtt all 2>/dev/null || echo "rocm-smi not available"

echo -e "\n=== HIP Memory Test ==="
# Compile and run HIP test if not already compiled
HIP_TEST_DIR="$(dirname "$0")"
if [ -f "$HIP_TEST_DIR/hip_mem_test.cpp" ]; then
    /opt/rocm/bin/hipcc "$HIP_TEST_DIR/hip_mem_test.cpp" -o /tmp/hip_mem_test 2>/dev/null
    export HSA_OVERRIDE_GFX_VERSION=11.5.1
    export HSA_ENABLE_SDMA=0
    /tmp/hip_mem_test
else
    echo "hip_mem_test.cpp not found"
fi

echo -e "\n=== rocminfo GPU Pools ==="
rocminfo 2>/dev/null | grep -A 20 "Agent 2" | grep -A 12 "Pool Info"
