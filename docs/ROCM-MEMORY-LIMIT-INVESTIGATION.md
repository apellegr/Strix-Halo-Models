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

## Investigation Update: 96GB BIOS VRAM Allocation (2026-01-15)

### Experiment: BIOS VRAM Carveout

Changed BIOS setting to allocate 96GB to the GPU as dedicated VRAM.

#### Results - WORSE Performance

| Metric | Before (Default) | After (96GB BIOS) |
|--------|------------------|-------------------|
| System RAM visible | 128 GB | 32 GB |
| Kernel VRAM | 0.5 GB | 96 GB |
| Kernel GTT | 115 GB | 115 GB |
| **HIP reported** | **61.35 GB** | **15.24 GB** |

The 96GB BIOS allocation **reduced** the HIP memory limit from 61GB to 15GB!

#### Root Cause Discovery

The memory limit comes from multiple layers:

1. **TTM pages_limit** - The TTM kernel module sets `pages_limit` based on system RAM
   ```
   /sys/module/ttm/parameters/pages_limit = 3995187 pages = 15.24 GB
   ```

2. **KFD Memory Banks** - KFD exposes this as the GPU memory pool
   ```
   /sys/class/kfd/kfd/topology/nodes/1/mem_banks/0/properties:
   heap_type 1        # GTT (not local VRAM!)
   size_in_bytes 16364285952  # = 15.24 GB
   ```

3. **KFD local_mem_size = 0** - The 96GB VRAM carveout is NOT exposed as local GPU memory
   ```
   /sys/class/kfd/kfd/topology/nodes/1/properties:
   local_mem_size 0   # Should be 96GB but shows 0!
   ```

4. **HSA/HIP Memory Pools** - rocminfo shows GPU pools at 15.24 GB
   ```
   Pool 1: Size 15980748 KB = 15.24 GB (COARSE GRAINED)
   Pool 2: Size 15980748 KB = 15.24 GB
   ```

#### The Formula

TTM calculates: `pages_limit = (system_RAM / 2) / 4KB`

With 96GB carved out for GPU:
- Remaining system RAM = 32 GB
- TTM pages_limit = 32GB / 2 = 16GB ≈ 15.24 GB (after overhead)

The BIOS VRAM carveout is visible to the kernel driver but **NOT** to KFD/HSA/HIP stack.

#### Key Insight

The ROCm stack treats Strix Halo as an APU with **no dedicated VRAM** regardless of BIOS settings. It always calculates GPU memory based on remaining system RAM, not the actual VRAM allocation.

### Next Step: Kernel Parameters

Testing these boot parameters to bypass the limit:

```bash
# In /etc/default/grub GRUB_CMDLINE_LINUX_DEFAULT:
amdgpu.no_system_mem_limit=1 ttm.pages_limit=24576000
```

Where:
- `amdgpu.no_system_mem_limit=1` - Disables artificial system memory limit
- `ttm.pages_limit=24576000` - Sets TTM limit to 96GB (24576000 × 4KB = 96GB)

#### Commands to Apply

```bash
sudo sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=.*/GRUB_CMDLINE_LINUX_DEFAULT="text iommu=pt amdgpu.gttsize=117760 amdgpu.no_system_mem_limit=1 ttm.pages_limit=24576000"/' /etc/default/grub
sudo update-grub
sudo reboot
```

#### After Reboot - Verification Commands

```bash
# Check TTM limit
cat /sys/module/ttm/parameters/pages_limit

# Check KFD memory
cat /sys/class/kfd/kfd/topology/nodes/1/mem_banks/0/properties

# Run HIP memory test
/tmp/hip_mem_test

# Check rocm-smi
rocm-smi --showmeminfo vram gtt all
```

## Investigation Update: TTM Kernel Params with 96GB BIOS Carveout (2026-01-15)

### Test Configuration

Applied kernel parameters with 96GB BIOS VRAM allocation still active:

```
BOOT_IMAGE=/boot/vmlinuz-6.18.1-061801-generic root=UUID=... ro text iommu=pt \
  amdgpu.gttsize=117760 amdgpu.no_system_mem_limit=1 ttm.pages_limit=24576000
```

### Results: TTM Limit Works, But BIOS Carveout Doesn't

| Metric | Value |
|--------|-------|
| System RAM visible | 30 GB (96GB carved out) |
| TTM pages_limit | 24576000 (96GB) |
| KFD mem_banks size | 100663296000 bytes = **93.75 GB** ✓ |
| KFD local_mem_size | **0** (VRAM not exposed!) |
| rocm-smi VRAM | 96 GB (kernel sees it) |
| rocm-smi GTT | 115 GB |
| HIP Total | 100.66 GB |
| HIP Free | **30.61 GB** |
| Max allocation | **31.47 GB** |

### Key Insight: BIOS Carveout Not Usable by HIP

The 96GB BIOS VRAM allocation is visible to the kernel driver (`rocm-smi` shows it), but:

1. **KFD exposes `local_mem_size=0`** - the VRAM isn't recognized as local GPU memory
2. **HIP can only use GTT pool** - limited to remaining system RAM (~30GB)
3. **Result: WORSE than default** - 31GB max vs original 61GB

The BIOS carveout reduces system RAM without providing usable GPU memory.

### Conclusion: Revert BIOS, Keep TTM Params

The TTM kernel parameters successfully raised the KFD memory limit to 93.75 GB.
The problem is the BIOS carveout - it's not exposed through the KFD/HSA/HIP path.

**Recommended configuration:**
- BIOS: Default (no carveout) → 128GB system RAM
- Kernel params: Keep `ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1`
- Expected result: HIP should see ~96GB allocatable memory

### Next Test: Default BIOS + TTM Params

After reverting BIOS to default:

```bash
# Verify TTM limit still in effect
cat /sys/module/ttm/parameters/pages_limit  # Should be 24576000

# Check system RAM
free -h  # Should show ~128GB

# Test HIP memory
hipcc -o /tmp/hip_mem_test hip_mem_test.cpp && /tmp/hip_mem_test

# Test large allocation (60+ GB)
# If successful, try loading Qwen3-235B with 55+ GPU layers
```

---

### References

- [Jeff Geerling: Increasing VRAM on AMD AI APUs](https://www.jeffgeerling.com/blog/2025/increasing-vram-allocation-on-amd-ai-apus-under-linux)
- [AMD KFD mem limit fix patch](https://www.mail-archive.com/amd-gfx@lists.freedesktop.org/msg128131.html)
- Linux 6.10+ has improved APU memory handling following MI300A approach

---

## Investigation Update: 64GB BIOS Carveout + TTM Params (2026-01-15)

### Test Configuration

- **BIOS VRAM carveout:** 64GB
- **Kernel params:** `ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760`

### Results

| Metric | Value |
|--------|-------|
| BIOS VRAM carveout | 64 GB |
| System RAM visible | 61 GB (128-64-overhead) |
| KFD mem_banks | 93.75 GB (TTM param working!) |
| KFD local_mem_size | 0 (VRAM not exposed) |
| rocm-smi VRAM | 64 GB |
| HIP Total | 93.75 GB |
| HIP Free | 58.97 GB |

### Allocation Tests

| Size | Result |
|------|--------|
| 50 GB | ✓ Success |
| 55 GB | ✓ Success |
| 58 GB | ✓ Success |
| 60 GB | ✓ Success |
| 63 GB | ✗ **OOM KILLED** |

### Root Cause of OOM

The critical mismatch:
1. **KFD advertises 93.75 GB** available (from TTM params override)
2. **Only 61 GB physical RAM** exists (64GB carved out by BIOS)
3. **BIOS VRAM (64GB) is NOT usable** by HIP/KFD - shows as `local_mem_size=0`

When HIP tried to allocate 63GB:
- It exceeded the 61GB of available system RAM
- Linux OOM killer terminated the process
- The 64GB VRAM carveout is visible to `rocm-smi` but NOT exposed to KFD/HSA/HIP

### Key Finding

**The BIOS VRAM carveout is fundamentally broken for ROCm on Strix Halo:**
- The carved-out memory becomes inaccessible to the OS
- KFD doesn't expose it as usable GPU memory (`local_mem_size=0`)
- Result: You lose RAM without gaining GPU memory

### Safe Allocation Limit

With 64GB BIOS carveout:
- **Maximum safe allocation:** ~58-60 GB
- **Actual usable for LLM layers:** ~55 GB (with margin)

### Recommendation

**Revert BIOS to default (no carveout):**
- This restores 128 GB system RAM
- TTM params (`pages_limit=24576000`) should allow ~96GB allocations
- Expected result: 80-90 GB safely allocatable for LLM inference

---

## SUCCESS: 512MB BIOS + TTM Params (2026-01-15)

### Final Working Configuration

- **BIOS VRAM:** 512MB (minimum)
- **Kernel params:** `ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760`

### Results: +27 GB More GPU Memory!

| Metric | Before | After |
|--------|--------|-------|
| System RAM | 128 GB | 122 GB visible |
| TTM pages_limit | default (~61GB) | 24576000 (96GB) |
| KFD mem_banks size | ~61 GB | **93.75 GB** |
| HIP Total | 61.35 GB | **93.75 GB** |
| HIP Free | 61.35 GB | **93.75 GB** |
| **Max Allocation** | **~61 GB** | **88.16 GB** |

### Allocation Test Results

| Size | Result |
|------|--------|
| 70 GB | ✓ Success |
| 80 GB | ✓ Success |
| 85 GB | ✓ Success |
| 88 GB | ✓ Success |
| 90 GB | ✗ Failed (out of memory) |
| **Max** | **88.16 GB** |

### Why It Works

The key was combining:
1. **No BIOS carveout** - Full 128 GB system RAM available
2. **TTM pages_limit=24576000** - Raises kernel memory pool to 96 GB
3. **amdgpu.no_system_mem_limit=1** - Disables artificial system memory cap

The previous tests with BIOS carveouts (64GB, 96GB) failed because:
- BIOS carveout reduces visible system RAM
- KFD doesn't expose BIOS-carved VRAM (`local_mem_size=0`)
- Result: Less RAM with no GPU memory gain

### Recommended /etc/default/grub

```bash
GRUB_CMDLINE_LINUX_DEFAULT="text iommu=pt amdgpu.gttsize=117760 amdgpu.no_system_mem_limit=1 ttm.pages_limit=24576000"
```

### Test History Summary

| Date | Config | Result |
|------|--------|--------|
| Original | 512MB BIOS, no TTM params | 61.35 GB HIP limit |
| Test 1 | 96GB BIOS carveout | 15.24 GB (worse!) |
| Test 2 | 96GB BIOS + TTM params | 31 GB usable, VRAM not exposed |
| Test 3 | 64GB BIOS + TTM params | OOM at 63GB (only 61GB RAM) |
| **Test 4** | **512MB BIOS + TTM params** | **✓ 88.16 GB SUCCESS!** |

---

## GPU Layer Testing Session (2026-01-15)

### Goal
Push GPU layer count beyond the previous 55-layer limit now that we have 88 GB allocatable memory.

### Test Environment
- BIOS: 512MB VRAM (minimum)
- Kernel params: `ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760`
- HIP reports: 93.75 GB total, 88.16 GB max allocation
- Model: Qwen3-235B-A22B-Thinking Q3_K_M (107 GB total, 95 layers)

### Test Results

| Layers | GPU Buffer | Load Time | Inference | Status |
|--------|------------|-----------|-----------|--------|
| 55 | 61 GB | **224s** | 22.7 pp, 9.3 tg tok/s | ✓ Working |
| 56 | 61.05 GB | >10 min | - | ✗ Timeout |
| 58 | 63.25 GB | >17 min | - | ✗ Timeout |
| 55 (retry) | 61 GB | 367s | 0.44 pp, 2.19 tg tok/s | ⚠ Degraded |
| 55 (retry 2) | 61 GB | >5 min | - | ✗ Timeout |

### Key Observations

1. **hipMalloc vs llama-server behavior differs**
   - Raw `hipMalloc` test: 88 GB allocation succeeds
   - llama-server with 56+ layers (61+ GB): hangs during tensor loading

2. **System degradation after failed attempts**
   - After failed 56/58 layer attempts, even 55 layers became slow/stuck
   - Performance dropped from 22.7/9.3 tok/s to 0.44/2.19 tok/s
   - Suggests SVM/unified memory state corruption

3. **The ~61 GB boundary**
   - 55 layers = 61 GB works
   - 56 layers = 61.05 GB hangs
   - The threshold appears to be around the old HIP limit (61.35 GB)

### Hypothesis

The TTM kernel params successfully raise the allocation limit for simple `hipMalloc` calls, but llama-server's tensor loading pattern (many sequential allocations, mmap usage) may trigger different behavior in the ROCm/SVM subsystem that still respects some internal limit.

Possible causes:
- KFD memory pool fragmentation
- SVM page migration overhead at larger sizes
- Different code paths for managed vs device memory
- mmap interaction with unified memory

### Next Steps After Reboot

1. **Verify baseline** - Confirm 55 layers still works at ~224s load time
2. **Test without mmap** - Try `-nmmp` or `--no-mmap` flag if available
3. **Test with UMA build** - Rebuild llama.cpp with `GGML_HIP_UMA=ON`
4. **Incremental testing** - If 55 works, try 55 → 56 with careful monitoring
5. **Monitor dmesg** - Watch for SVM/KFD warnings during loading

### Commands for Post-Reboot

```bash
# Verify system state
free -h
cat /sys/module/ttm/parameters/pages_limit  # Should be 24576000
rocm-smi --showmeminfo gtt

# Quick HIP allocation test
./hip_alloc_test 70  # Should succeed

# Test 55 layers (baseline)
export HSA_ENABLE_SDMA=0 HSA_OVERRIDE_GFX_VERSION=11.5.1 HIP_VISIBLE_DEVICES=0 GPU_MAX_HEAP_SIZE=100
llama-server -m "models/massive/qwen3-235b-thinking/Q3_K_M/Qwen3-235B-A22B-Thinking-2507-Q3_K_M-00001-of-00003.gguf" \
  -ngl 55 --host 0.0.0.0 --port 8081 -c 4096 -np 1 -t 16 -b 1024
```

### Status: REBOOT REQUIRED

System is in degraded state from failed high-memory allocation attempts. Reboot needed to restore clean SVM/memory state.

---

## BREAKTHROUGH: --no-mmap Fix (2026-01-15)

### The Problem
After applying TTM kernel parameters, raw `hipMalloc` allocations up to 88 GB succeeded, but llama-server still hung when loading 56+ GPU layers. The server would get stuck during tensor loading with mmap enabled.

### Root Cause
The interaction between mmap (memory-mapped file I/O) and ROCm's SVM (Shared Virtual Memory) / unified memory system causes hangs when loading large models. The mmap code path triggers different behavior in the HIP/KFD stack than direct memory allocations.

### The Fix
Add `--no-mmap` flag to llama-server to disable memory-mapped model loading:

```bash
llama-server -m model.gguf -ngl 80 --no-mmap --host 0.0.0.0 --port 8081
```

### Results Summary

| Layers | GPU Buffer | Load Time | Prompt (tok/s) | Gen (tok/s) | Status |
|--------|------------|-----------|----------------|-------------|--------|
| 55 (old max) | 61 GB | ~4 min | 37 | 9.4 | ✓ With mmap |
| 56 | 62 GB | hang | - | - | ✗ mmap hangs |
| 56 | 62 GB | ~2 min | 37 | 9.4 | ✓ --no-mmap |
| 60 | 66.5 GB | ~2 min | - | - | ✓ --no-mmap |
| 70 | 77.5 GB | ~2.5 min | - | - | ✓ --no-mmap |
| 80 | 88.6 GB | ~3 min | - | - | ✓ --no-mmap |
| **81** | **89.7 GB** | **~3.5 min** | **94** | **6.3** | **✓ --no-mmap MAX** |
| 82 | 92 GB | - | - | - | ✗ OOM |
| 85 | 95 GB | - | - | - | ✗ OOM |

### Performance Improvement

| Metric | Before (55 layers) | After (81 layers) | Improvement |
|--------|-------------------|-------------------|-------------|
| GPU layers | 55/95 (58%) | 81/95 (85%) | **+47% more layers** |
| GPU memory | 61 GB | 90 GB | **+29 GB (+48%)** |
| Prompt processing | 37 tok/s | 94 tok/s | **+154%** |
| Token generation | 9.4 tok/s | 6.3 tok/s | -33% (more offload) |

**Note:** Token generation speed slightly decreases because more layers means larger per-layer memory transfers. However, prompt processing speed more than doubles because more computation happens on GPU.

### Optimal Configuration

For Qwen3-235B Q3_K_M on Strix Halo with 128 GB RAM:

```bash
# Environment
export HSA_ENABLE_SDMA=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HIP_VISIBLE_DEVICES=0
export GPU_MAX_HEAP_SIZE=100

# Server command with --no-mmap
llama-server \
  -m "models/massive/qwen3-235b-thinking/Q3_K_M/Qwen3-235B-A22B-Thinking-2507-Q3_K_M-00001-of-00003.gguf" \
  -ngl 81 \
  --no-mmap \
  --host 0.0.0.0 \
  --port 8081 \
  -c 4096 \
  -np 1 \
  -t 16 \
  -b 1024
```

### Technical Details

1. **Why mmap hangs:** When llama.cpp uses mmap, it maps the GGUF file directly into virtual memory and then copies tensors to GPU. On Strix Halo, this triggers SVM page migration that interacts poorly with the large GTT allocations, causing the process to hang during tensor loading.

2. **Why --no-mmap works:** Without mmap, llama.cpp reads the file into a malloc'd buffer first, then copies to GPU. This avoids the problematic mmap+SVM interaction.

3. **Memory overhead:** --no-mmap uses more system RAM temporarily during loading (needs to hold the file buffer), but since Strix Halo has 128 GB unified memory, this is not a problem.

### Final Recommended Setup

| Setting | Value |
|---------|-------|
| BIOS VRAM | 512 MB (minimum, no carveout) |
| Kernel params | `ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760` |
| llama-server flag | `--no-mmap` |
| Max GPU layers | 81 (for Qwen3-235B Q3_K_M) |
| Max GPU memory | ~90 GB |

---

## Memory Bandwidth Analysis (2026-01-15)

### Benchmark Results

| Test | Bandwidth | Notes |
|------|-----------|-------|
| CPU STREAM (Triad) | 112.64 GB/s | DDR5 system memory |
| GPU Internal (4GB arrays) | 236 GB/s | Includes Infinity Cache benefit |
| GPU Internal (20GB arrays) | 205 GB/s | Cache miss, still cached |
| Host -> Device Transfer | 85 GB/s | Actual data movement |
| Device -> Host Transfer | 82 GB/s | Actual data movement |

### Analysis

The Strix Halo APU has:
- **DDR5-7200 dual channel**: ~115 GB/s theoretical, 112 GB/s measured
- **96 MB Infinity Cache**: Provides 2x bandwidth amplification for cached data
- **Unified Memory Architecture**: GPU and CPU share the same DDR5

For LLM inference, model weights don't fit in the 96MB Infinity Cache, so each token generation requires fetching ~8GB of active weights from main memory at ~85 GB/s.

### LLM Throughput Calculation

```
Qwen3-235B MoE (Q3_K_M):
- Total weights: 107 GB
- Active weights per token: ~8 GB (8/128 experts × 3 bits)
- H2D bandwidth: 85 GB/s
- Theoretical max: 85 GB/s ÷ 8 GB = 10.6 tok/s
- Measured: 9 tok/s (85% efficiency)
```

### Power vs Bandwidth

| Metric | Value |
|--------|-------|
| Peak GPU Power | 115W |
| Sustained Power | 85W |
| GPU Utilization | 78-84% |
| Memory Bound? | Yes |

The GPU is not compute-bound but memory-bound. Increasing GPU power/clocks won't improve throughput because the bottleneck is DDR5 bandwidth.

### Potential Improvements

1. **Faster DDR5** (DDR5-8400): Could increase throughput by ~15%
2. **Smaller quantization** (Q2_K): Reduces memory reads per token
3. **Speculative decoding**: Amortizes memory reads over multiple tokens
4. **Prompt batching**: Already at 546 tok/s for long prompts

---

## Contact

This investigation was performed to maximize LLM inference performance on Strix Halo.
~~The artificial 61 GB limit prevents full utilization of the 128 GB unified memory.~~

**RESOLVED:** With TTM kernel params + `--no-mmap`, we can now use up to 90 GB of GPU memory for LLM inference. Performance is memory-bandwidth limited at ~9 tok/s for Qwen3-235B.
