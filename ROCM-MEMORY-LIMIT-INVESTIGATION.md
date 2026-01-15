# ROCm Memory Limit Investigation on AMD Strix Halo APU

**Date:** 2025-01-15  
**System:** AMD Ryzen AI Max+ 395 (Strix Halo) with 128GB Unified Memory  
**ROCm Version:** 7.1.1  
**Kernel:** 6.18.1-061801-generic  
**OS:** Ubuntu 25.04 (Plucky)

## Executive Summary

The HIP runtime artificially limits GPU memory allocation to **61.35 GB** on Strix Halo APUs, despite the kernel reporting 115 GB of GTT memory available. This prevents loading large LLM models (like Qwen3-235B) with more than ~50-55 GPU layers.

## System Configuration

### Hardware
- **CPU/APU:** AMD Ryzen AI Max+ 395 (Strix Halo)
- **GPU:** Integrated RDNA 3.5 (gfx1151)
- **Total System RAM:** 128 GB
- **Architecture:** Unified Memory (CPU and GPU share system RAM)

### Software
- **Kernel:** 6.18.1-061801-generic
- **ROCm:** 7.1.1
- **HIP:** 7.1.52802
- **Compiler:** GCC 15.0.1 / ROCm Clang 20.0.0

### Kernel Boot Parameters
```
amdgpu.gttsize=117760 iommu=pt
```

## The Problem

When attempting to load a large model (Qwen3-235B-Thinking Q3_K_M, ~90GB) with 55+ GPU layers:

```
ggml_backend_cuda_buffer_type_alloc_buffer: allocating 61386.27 MiB on device 0: cudaMalloc failed: out of memory
```

The allocation fails at approximately **61 GB**, even though the system has 128 GB of RAM and the kernel allows 115 GB for GPU use.

## Evidence Collected

### 1. Kernel Reports 115 GB GTT Available

```bash
$ cat /sys/class/drm/card0/device/mem_info_gtt_total
123480309760  # = 115.00 GB

$ cat /sys/class/drm/card0/device/mem_info_gtt_used  
18653184      # = 0.01 GB (nearly all free)
```

### 2. TTM Module Allows 100 GB

```bash
$ cat /sys/module/ttm/parameters/pages_limit
26214400  # = 100 GB (26214400 pages × 4KB)
```

### 3. HIP Runtime Reports Only 61.35 GB

Test program output:
```c
#include <hip/hip_runtime.h>
#include <stdio.h>
int main() {
    size_t free_mem, total_mem;
    hipMemGetInfo(&free_mem, &total_mem);
    printf("Total GPU memory: %.2f GB\n", total_mem / 1024.0 / 1024.0 / 1024.0);
    printf("Free GPU memory:  %.2f GB\n", free_mem / 1024.0 / 1024.0 / 1024.0);
    return 0;
}
```

**Output:**
```
Total GPU memory: 61.35 GB
Free GPU memory:  61.35 GB
```

### 4. Memory Breakdown

| Source | Reported Value | Notes |
|--------|---------------|-------|
| System RAM | 128 GB | Total physical memory |
| Kernel GTT | 115 GB | `mem_info_gtt_total` |
| Kernel VRAM | 0.5 GB | `mem_info_vram_total` (integrated GPU) |
| TTM pages_limit | 100 GB | Kernel module parameter |
| **HIP Runtime** | **61.35 GB** | **Artificially limited** |

### 5. The 61.35 GB Calculation

The 61.35 GB appears to be approximately:
- 53% of 115 GB GTT
- ~48% of 128 GB system RAM
- Possibly hardcoded as `0.5 * system_ram` or similar formula

## What We Tried

### 1. Environment Variables (No Effect)
```bash
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
```
These did not increase the limit.

### 2. GGML_HIP_UMA=ON Build (No Effect)
Rebuilt llama.cpp with UMA support (uses `hipMallocManaged` instead of `hipMalloc`).
The same 61.35 GB limit applies to managed memory allocations.

### 3. Kernel TTM Parameters (Partially Effective)
```bash
# In /etc/default/grub or kernel cmdline:
ttm.pages_limit=26214400
ttm.page_pool_size=26214400
amdgpu.gttsize=117760
```
This increased the kernel-level limit to 100-115 GB, but the HIP runtime limit remained at 61.35 GB.

### 4. Clearing Caches and Memory (No Effect)
```bash
sync && echo 3 > /proc/sys/vm/drop_caches
```
The limit is not related to memory fragmentation.

## Root Cause Analysis

The limit is **hardcoded in the HIP runtime** (libamdhip64.so), not in the kernel.

The HIP runtime queries the GPU properties and calculates a maximum heap size based on:
1. The reported VRAM size (only 512 MB for integrated GPU)
2. The GTT size
3. An internal formula that caps allocations at ~50% of available memory

For APUs like Strix Halo, this formula produces an artificially low limit because:
- The "VRAM" is tiny (512 MB)
- The GTT (system memory) is treated differently than discrete GPU VRAM
- The runtime doesn't recognize that 128 GB of unified memory is available

## Reproduction Steps

1. Install ROCm 7.1.1 on a Strix Halo system with 128 GB RAM
2. Set kernel parameters for large GTT: `amdgpu.gttsize=117760`
3. Run the test program above to confirm 61.35 GB limit
4. Try to allocate more than 61 GB with `hipMalloc` - it will fail

## Requested Fix

The HIP runtime should:
1. Recognize Strix Halo APUs (gfx1151) as having unified memory
2. Use the actual available GTT memory (115+ GB) as the allocation limit
3. Or provide an environment variable to override the limit (e.g., `HIP_MAX_HEAP_SIZE`)

## Workaround (Current)

Limit GPU layer offloading to stay under 61 GB:
- Qwen3-235B Q3_K_M: 50 GPU layers maximum (~55-58 GB used)
- Performance: ~10 tok/s generation, ~25 tok/s prompt processing

## Files and Configurations

### Working llama.cpp Build Configuration
```bash
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_C_COMPILER=/usr/bin/gcc-15 \
    -DCMAKE_CXX_COMPILER=/usr/bin/g++-15 \
    -DCMAKE_CXX_FLAGS="-march=znver5 -mtune=znver5" \
    -DGGML_HIP=ON \
    -DAMDGPU_TARGETS=gfx1151 \
    -DGGML_HIPBLAS=ON \
    -DGGML_NATIVE=ON \
    -DGGML_AVX512=ON \
    -DGGML_AVX512_VBMI=ON \
    -DGGML_AVX512_VNNI=ON \
    -DGGML_AVX512_BF16=ON
```

### ROCm CMake Files Created
Due to ROCm 7.1.1 missing some cmake files, we created:
- `/opt/rocm/lib/cmake/hip/hip-config.cmake`
- `/opt/rocm/lib/cmake/hip-lang/hip-lang-config.cmake`
- `/opt/rocm/bin/hipcc` (wrapper script)
- `/opt/rocm/bin/hipconfig` (wrapper script)

### Environment Variables for Running
```bash
export LD_LIBRARY_PATH=/opt/rocm/lib:~/.local/lib:$LD_LIBRARY_PATH
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export HSA_OVERRIDE_GFX_VERSION=11.5.1
```

## Related Issues

- This may affect all APUs with large unified memory (Strix Halo, future APUs)
- Similar issues reported for other ROCm versions on integrated graphics
- The limit may be defined in `hip/src/hip_memory.cpp` or device property initialization code

## Contact

This investigation was performed to maximize LLM inference performance on Strix Halo.
The artificial 61 GB limit prevents full utilization of the 128 GB unified memory.
