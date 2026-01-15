# Memory Bandwidth Benchmarks for Strix Halo

Benchmark tools to measure memory bandwidth on AMD Strix Halo APU systems.

## Benchmarks

| File | Description | What it measures |
|------|-------------|------------------|
| `mem_bandwidth.c` | CPU STREAM benchmark | DDR5 system memory bandwidth |
| `gpu_bandwidth.cpp` | GPU device memory | HIP kernel memory bandwidth (includes Infinity Cache) |
| `gpu_bandwidth_large.cpp` | GPU large allocation | Memory bandwidth with 10-30GB arrays |
| `transfer_bandwidth.cpp` | Host-Device transfer | Actual H2D/D2H data movement speed |
| `hip_alloc_test.cpp` | HIP allocation test | Maximum GPU memory allocation size |

## Building

```bash
# Build all benchmarks
make all

# Or build individually
make cpu         # CPU STREAM benchmark
make gpu         # GPU device memory benchmark
make gpu_large   # GPU large allocation benchmark
make transfer    # Host-Device transfer benchmark
```

## Running

```bash
# CPU memory bandwidth (uses OpenMP)
OMP_NUM_THREADS=16 ./mem_bandwidth

# GPU benchmarks (need ROCm environment)
export HSA_OVERRIDE_GFX_VERSION=11.5.1
export HSA_ENABLE_SDMA=0

./gpu_bandwidth
./gpu_bandwidth_large
./transfer_bandwidth
```

## Results on Strix Halo (AMD Ryzen AI Max+ 395, 128GB DDR5)

### Measured Bandwidth

| Test | Bandwidth | Notes |
|------|-----------|-------|
| CPU STREAM (Triad) | 112.64 GB/s | DDR5 system memory |
| GPU Internal (4GB) | 236 GB/s | Infinity Cache benefit |
| GPU Internal (20GB) | 205 GB/s | Beyond cache size |
| Host -> Device | 85 GB/s | Actual data movement |
| Device -> Host | 82 GB/s | Actual data movement |

### Key Insights

1. **DDR5 Bandwidth**: ~112 GB/s (likely DDR5-7200 dual channel)
2. **Infinity Cache**: 96MB cache provides ~2x bandwidth amplification
3. **LLM Bottleneck**: For large models (>cache size), effective bandwidth is H2D rate (~85 GB/s)

### LLM Inference Implications

For Qwen3-235B MoE (Q3_K_M):
- Active weights per token: ~8 GB
- Theoretical max: 85 GB/s ÷ 8 GB = 10.6 tok/s
- Measured: 9 tok/s (85% efficiency)

The system is memory-bandwidth bound, not compute bound.

## Requirements

- GCC with OpenMP support
- ROCm/HIP for GPU benchmarks
- AMD Strix Halo or compatible APU
