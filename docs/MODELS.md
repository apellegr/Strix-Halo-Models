# Strix Halo 395+ LLM Model Guide

## Hardware Overview

The AMD Ryzen AI Max+ 395 (Strix Halo) with 128GB LPDDR5X-8000 is exceptionally capable for local LLM inference:

| Spec | Value |
|------|-------|
| CPU | 16 Zen 5 cores (up to 5.1 GHz) |
| GPU | Radeon 8060S (40 RDNA 3.5 CUs) |
| Peak FP16 | ~59 TFLOPS |
| Memory | 128GB LPDDR5X-8000 |
| Bandwidth | ~212-256 GB/s |
| GPU Memory (Linux GTT) | ~90-93GB (with kernel params) |
| Host-to-Device BW | ~85 GB/s (LLM bottleneck) |

## Quick Start

```bash
# Download essential models
./scripts/setup/download_strix_halo_models.sh --essential

# Or run interactive menu
./scripts/setup/download_strix_halo_models.sh

# Preview without downloading
DRY_RUN=1 ./scripts/setup/download_strix_halo_models.sh --all

# Custom directory
MODELS_DIR=/mnt/nvme/models ./scripts/setup/download_strix_halo_models.sh
```

---

## System Configuration

Exact software stack used for all benchmarks (March 10, 2026):

| Component | Version / Details |
|-----------|-------------------|
| **OS** | Ubuntu 25.10 |
| **Kernel** | 6.17.0-14-generic |
| **ROCm** | 7.2.0 |
| **HIP Runtime** | 7.2.26015.70200-43 |
| **rocBLAS** | 5.2.0.70200-43 |
| **amdgpu driver** | In-kernel (6.17.0-14-generic) |
| **llama.cpp** | [Lychee-Technology](https://github.com/Lychee-Technology/llama.cpp) build b8280, commit `b2e1427` |
| **ggml libs** | 0.9.7 (libggml-base, libggml-cpu, libggml-hip) |
| **libllama** | 0.0.1 |
| **Compiler** | Clang 22.0.0 (ROCm HIP), GCC 15.2.0 (system) |
| **GPU target** | gfx1151 (RDNA 3.5) |

### Kernel Parameters (required for full GPU memory)

```
amdgpu.gttsize=117760 amdgpu.no_system_mem_limit=1 ttm.pages_limit=24576000
```

This unlocks 115 GB GTT (up from ~61 GB default). Without these, most models above 32B will fail to fully offload.

### Environment Variables

```bash
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
```

### Benchmark Command

All results collected with `llama-bench` using these flags:

```bash
llama-bench -m <model> -ngl 999 -t 16 -b <batch> -ub <ubatch> \
    -p 512 -n 128 -r 3 -fa 1 -mmp 0 -o json
```

- `-p 512 -n 128`: 512 prompt tokens, 128 generation tokens
- `-r 3`: 3 repetitions, results averaged
- `-fa 1`: Flash attention enabled
- `-mmp 0`: mmap disabled (required for large models on unified memory)
- `-ngl 999`: Full GPU offload (except Qwen3-235B at `-ngl 80`)

---

## Complete Benchmark Results

Fully GPU offloaded (ngl=999) unless noted. Flash attention enabled. 3 repetitions averaged.

### Fast Models (3-9B) — 29-69 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) |
|-------|-------|------|----------------|-------------------|
| Llama 3.2 3B | Q6_K | 2.6 GB | 1,538 | **69.0** |
| GLM-4.7 Flash | Q4_K_M | 17.1 GB | 897 | **54.1** |
| Qwen 2.5 7B | Q5_K_M | 5.1 GB | 1,140 | **40.7** |
| Mistral 7B v0.3 | Q5_K_M | 4.8 GB | 895 | **39.0** |
| Llama 3.1 8B | Q5_K_M | 5.3 GB | 893 | **37.2** |
| Gemma 2 9B | Q5_K_M | 6.2 GB | 710 | **29.0** |

GLM-4.7 Flash is a MoE model — despite its 17 GB size, it achieves 54 tok/s TG because only a fraction of parameters are active per token.

### Balanced Models (14-32B) — 11-21 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) |
|-------|-------|------|----------------|-------------------|
| Hermes 4 14B | Q5_K_M | 9.8 GB | 558 | **21.1** |
| Qwen 2.5 14B | Q5_K_M | 9.8 GB | 537 | **20.9** |
| Phi-4 14B | Q5_K_M | 9.9 GB | 555 | **20.8** |
| Mistral Small 24B | Q4_K_M | 13.3 GB | 352 | **15.0** |
| Gemma 2 27B | Q4_K_M | 15.5 GB | 310 | **12.7** |
| Qwen 2.5 32B | Q4_K_M | 18.5 GB | 266 | **11.0** |
| DeepSeek R1 32B | Q4_K_M | 18.5 GB | 255 | **11.0** |

### Coding Models — 11-70 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) | Notes |
|-------|-------|------|----------------|-------------------|-------|
| **Qwen3 Coder 30B** | Q4_K_M | 17.3 GB | 812 | **69.6** | MoE (3B active) |
| **DeepSeek Coder V2 16B** | Q5_K_M | 11.0 GB | 1,227 | **68.0** | MoE |
| Qwen 2.5 Coder 7B | Q5_K_M | 5.1 GB | 1,134 | **40.7** | |
| Qwen 2.5 Coder 14B | Q6_K | 11.3 GB | 489 | **18.2** | |
| Qwen 2.5 Coder 32B | Q4_K_M | 18.5 GB | 264 | **11.0** | |
| CodeLlama 70B | Q4_K_M | 38.6 GB | 112 | **5.0** | |

The two MoE coding models (Qwen3 Coder 30B and DeepSeek Coder V2) are standouts — they achieve 6x the TG speed of similarly-sized dense models while maintaining strong code quality.

### Tool Calling & Function Calling — 25-37 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) |
|-------|-------|------|----------------|-------------------|
| Functionary v3.2 | Q5_K_M | 5.3 GB | 874 | **37.1** |
| xLAM-2 8B | Q5_K_M | 5.3 GB | 882 | **37.0** |
| Hermes 2 Pro 8B | Q6_K | 6.1 GB | 642 | **33.0** |
| Mistral Nemo 12B | Q5_K_M | 8.1 GB | 643 | **25.0** |

### Vision Models — 28-41 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) |
|-------|-------|------|----------------|-------------------|
| Qwen 2.5 VL 7B | Q5_K_M | 5.1 GB | 1,132 | **40.6** |
| LLaVA 1.6 7B | Q5_K_M | 4.8 GB | 870 | **38.9** |
| Pixtral 12B | Q4_K_M | 7.0 GB | 645 | **28.2** |

### Large Models (70B dense) — 3.5-5.0 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) |
|-------|-------|------|----------------|-------------------|
| Hermes 4 70B | Q4_K_M | 39.6 GB | 112 | **5.0** |
| Hermes 3 70B | Q4_K_M | 39.6 GB | 109 | **5.0** |
| DeepSeek R1 Llama 70B | Q4_K_M | 39.6 GB | 111 | **5.0** |
| Command R+ 104B | Q3_K_M | 47.5 GB | 91 | **4.2** |
| Llama 3.3 70B | Q6_K | 53.9 GB | 86 | **3.8** |
| Qwen 2.5 72B | Q6_K | 59.9 GB | 68 | **3.4** |

Dense 70B models are heavily memory-bandwidth bound. Q4_K_M variants (~40 GB) achieve ~5 tok/s, while Q6_K variants (~54-60 GB) drop to 3.4-3.8 tok/s due to the larger weight transfer per token.

### Massive Models (100B+) — 7.8-51 tok/s

| Model | Quant | Size | Prompt (tok/s) | Generation (tok/s) | Notes |
|-------|-------|------|----------------|-------------------|-------|
| **GPT-OSS 120B** | MXFP4 | 59.0 GB | 174 | **51.1** | ISWA architecture |
| **Llama 4 Scout** | Q4_K_M | 60.9 GB | 282 | **19.2** | MoE (17B-16E, 109B total) |
| **Qwen 3.5 122B-A10B** | MXFP4 | 69.5 GB | 136 | **18.3** | MoE (10B active), hybrid SSM |
| **Qwen3-235B Thinking** | Q3_K_M | 104.7 GB | 135 | **7.8** | MoE (22B active), 80/95 GPU layers |
| Mistral Large 123B | Q3_K_L | 60.1 GB | 74 | **2.8** | Dense, older binary data |

GPT-OSS 120B's 51 tok/s is remarkable for a 120B model — its ISWA architecture (sliding window attention) keeps the KV cache small (~4.5 GB at 131K context), allowing more memory for compute.

---

## Performance Analysis

### Why MoE Models Are Fast

Mixture-of-Experts (MoE) models only activate a subset of parameters per token. On memory-bandwidth-bound hardware like Strix Halo, this is transformative:

| Model | Total Params | Active Params | TG (tok/s) | Speedup vs Dense |
|-------|-------------|---------------|------------|-----------------|
| Qwen3 Coder 30B | 30B | 3B | 69.6 | ~6x vs dense 32B |
| DeepSeek Coder V2 16B | 16B | ~2B | 68.0 | ~6x vs dense 16B |
| GLM-4.7 Flash | — | — | 54.1 | — |
| GPT-OSS 120B | 120B | — | 51.1 | ~10x vs dense 120B |
| Llama 4 Scout | 109B | 17B | 19.2 | ~4x vs dense 70B |
| Qwen 3.5 122B-A10B | 122B | 10B | 18.3 | ~4x vs dense 70B |
| Qwen3-235B Thinking | 235B | 22B | 7.8 | — |

### TG Speed vs. Model Size

Token generation speed is almost entirely determined by how much weight data must be read per token:

| Size Range | Typical TG | Examples |
|------------|-----------|----------|
| 3-5 GB | 37-69 tok/s | Llama 3.2 3B, Mistral 7B |
| 5-7 GB | 29-41 tok/s | Qwen 2.5 7B, Gemma 2 9B |
| 8-10 GB | 21-26 tok/s | Phi-4, Solar 10.7B |
| 11-13 GB | 15-18 tok/s | Mistral Small 24B, Qwen 2.5 Coder 14B |
| 15-19 GB | 11-13 tok/s | Qwen 2.5 32B, DeepSeek R1 32B |
| 39-40 GB | 5.0 tok/s | All Q4_K_M 70B models |
| 54-60 GB | 3.4-3.8 tok/s | Q6_K 70B models |

MoE models break this pattern because their *effective* size per token is much smaller than their on-disk size.

---

## Model Selection Guide

### For Coding

| Priority | Model | TG (tok/s) | Why |
|----------|-------|-----------|-----|
| Fastest | Qwen3 Coder 30B (MoE) | 69.6 | MoE — 6x faster than dense, strong quality |
| Fast + Quality | DeepSeek Coder V2 16B (MoE) | 68.0 | Excellent code completion |
| Best Quality | Qwen 2.5 Coder 32B | 11.0 | Dense — highest benchmark scores |
| Large Context | CodeLlama 70B | 5.0 | 100K context, slow but capable |

### For General Chat

| Priority | Model | TG (tok/s) | Why |
|----------|-------|-----------|-----|
| Quick | Qwen 2.5 7B | 40.7 | Fast and capable for simple tasks |
| Balanced | Qwen 2.5 32B | 11.0 | Good quality/speed tradeoff |
| Best Quality | Qwen 2.5 72B (Q6_K) | 3.4 | Slow but highest quality |

### For Reasoning / Math

| Priority | Model | TG (tok/s) | Why |
|----------|-------|-----------|-----|
| Fast | DeepSeek R1 32B | 11.0 | R1 distillation, strong reasoning |
| Maximum | Qwen3-235B Thinking | 7.8 | 235B MoE with extended thinking |

### For Tool / Function Calling

| Priority | Model | TG (tok/s) | Why |
|----------|-------|-----------|-----|
| Fast | Functionary v3.2 | 37.1 | Purpose-built for function calling |
| Quality | Hermes 4 14B | 21.1 | Strong tool use, larger context |
| Maximum | Hermes 4 70B | 5.0 | Best tool calling quality, slow |

### For Vision Tasks

| Priority | Model | TG (tok/s) | Why |
|----------|-------|-----------|-----|
| Fast | LLaVA 1.6 7B | 38.9 | Quick image understanding |
| Quality | Qwen 2.5 VL 7B | 40.6 | Better visual reasoning |
| Balanced | Pixtral 12B | 28.2 | Good quality, moderate speed |

### For Claude Code (Local LLM)

Recommended multi-model setup:

| Role | Model | TG (tok/s) | Why |
|------|-------|-----------|-----|
| **Background** | Llama 3.2 3B | 69.0 | Handles simple tasks instantly |
| **Default** | Qwen 2.5 Coder 32B | 11.0 | Strong coding, good context |
| **Reasoning** | DeepSeek R1 32B | 11.0 | R1 architecture for complex tasks |

**Total memory: ~40 GB** (leaves room for system + context)

Setup: See [claude-code-router/README.md](../claude-code-router/README.md)

---

## Recommended Software Stack

### llama.cpp (Best Performance)
```bash
# Build with ROCm support for Strix Halo
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151
cmake --build build --config Release -j

# Or use the included install script
./scripts/setup/install-llama-cpp.sh
```

### LM Studio
- User-friendly GUI
- Works well on Strix Halo
- Automatic model management
- Download: https://lmstudio.ai

### Ollama
```bash
curl -fsSL https://ollama.com/install.sh | sh
ollama run llama3.3:70b-instruct-q4_K_M
```

---

## Linux Configuration

### 1. Unlock Full GPU Memory

By default, ROCm limits GPU memory to ~61 GB. Add these kernel parameters to `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="... ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760"
```

Then `sudo update-grub && sudo reboot`. This unlocks ~90+ GB of GPU memory.

### 2. ROCm Environment Variables

Critical for Strix Halo unified memory (set automatically by all scripts):

```bash
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
```

### 3. Kernel Version
Linux 6.15+ recommended for best Strix Halo performance.

---

## Context Length & Memory

With 128 GB unified memory:

| Model | Context | Approx. Memory |
|-------|---------|----------------|
| 7B Q5 | 32K | ~7 GB |
| 32B Q4 | 8K | ~20 GB |
| 32B Q4 | 32K | ~26 GB |
| 70B Q4 | 8K | ~42 GB |
| 70B Q4 | 32K | ~52 GB |
| Qwen3-235B Q3 | 16K | ~105 GB |
| GPT-OSS 120B MXFP4 | 131K | ~64 GB |

GPT-OSS 120B is unique — its ISWA sliding window attention means context length has minimal impact on memory (~4.5 GB KV cache at 131K tokens).

## Quantization Guide

| Quant | Quality Loss | Size Reduction | Recommended For |
|-------|--------------|----------------|-----------------|
| Q8_0 | Minimal | ~50% | Small models, max quality |
| Q6_K | Very low | ~60% | Models up to 32B |
| Q5_K_M | Low | ~65% | Models up to 70B |
| Q4_K_M | Acceptable | ~70% | 70B models |
| Q3_K_M | Noticeable | ~80% | 100B+ models |
| MXFP4 | Low | ~75% | MoE models (when available) |

## Troubleshooting

### Out of Memory
- Use lower quantization (Q6 → Q4 → Q3)
- Reduce context length
- Use `--no-mmap` for large models
- Check GPU memory: `cat /sys/class/drm/card*/device/mem_info_gtt_total`

### Slow Performance
- Ensure full GPU offloading: `-ngl 999`
- Check kernel version (6.15+ recommended)
- Verify kernel params for GPU memory are applied

### Model Won't Load
- Verify GPU memory limit is unlocked (kernel params above)
- Check ROCm detects gfx1151: `rocm-smi`
- Try `--no-mmap` flag
- Some older GGUF files may not load with newer llama.cpp builds

---

## Resources

- [Strix Halo Homelab Wiki](https://strixhalo-homelab.d7.wtf/)
- [Framework Community Tests](https://community.frame.work/t/amd-strix-halo-ryzen-ai-max-395-gpu-llm-performance-tests/72521)
- [LHL's Strix Halo Testing](https://github.com/lhl/strix-halo-testing)
- [kyuz0's Toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)

## Total Storage Requirements

| Category | Approximate Size |
|----------|-----------------|
| Fast Models | ~25 GB |
| Balanced Models | ~80 GB |
| Large Models | ~130 GB |
| Massive Models | ~160 GB |
| Coding Models | ~80 GB |
| Vision Models | ~35 GB |
| Specialized | ~125 GB |
| **Essential Pack** | **~150 GB** |
| **Everything** | **~600 GB+** |
