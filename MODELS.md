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
| GPU Memory (Linux GTT) | ~115-120GB |
| GPU Memory (Windows) | Up to 96GB |

## Quick Start

```bash
# Make the script executable
chmod +x download_strix_halo_models.sh

# Run interactive menu
./download_strix_halo_models.sh

# Or download essential models directly
./download_strix_halo_models.sh --essential

# Preview without downloading
DRY_RUN=1 ./download_strix_halo_models.sh --all

# Custom directory
MODELS_DIR=/mnt/nvme/models ./download_strix_halo_models.sh
```

## Model Performance Expectations

Based on benchmarks with llama.cpp on Strix Halo (AMD Ryzen AI Max+ 395):

### Measured Benchmarks (January 2026)

These results are from actual benchmarks using `./benchmark-model.sh --optimize`:

| Model | GPU Layers | Prompt (tok/s) | Generation (tok/s) | Memory |
|-------|------------|----------------|-------------------|--------|
| **llama-3.2-3b** | 50 | 2,154 | **68.8** | ~8GB |
| **deepseek-coder-v2-16b** | 80 | 1,164 | **63.2** | ~17GB |
| **qwen2.5-coder-32b** | 80 | 317 | **10.5** | ~24GB |
| **deepseek-r1-32b** | 80 | 316 | **10.5** | ~24GB |
| **qwen3-235b-thinking** | 50 | 129 | **8.3** | ~51GB |

### Fast Tier (3-9B models) - 50-70+ tok/s
| Model | Quant | Size | Tokens/sec |
|-------|-------|------|------------|
| Llama 3.2 3B | Q6_K | ~3GB | **68.8** (measured) |
| Mistral 7B | Q5_K_M | ~5GB | 30-45 |
| Qwen 2.5 7B | Q5_K_M | ~5GB | 30-40 |
| Gemma 2 9B | Q5_K_M | ~7GB | 25-35 |

### Balanced Tier (14-32B models) - 10-25 tok/s
| Model | Quant | Size | Tokens/sec |
|-------|-------|------|------------|
| DeepSeek Coder V2 16B | Q5_K_M | ~12GB | **63.2** (measured, MoE) |
| Qwen 2.5 14B | Q5_K_M | ~10GB | 18-25 |
| Gemma 2 27B | Q4_K_M | ~17GB | 12-18 |
| Qwen 2.5 Coder 32B | Q4_K_M | ~19GB | **10.5** (measured) |
| DeepSeek R1 32B | Q4_K_M | ~19GB | **10.5** (measured) |

### Large Tier (70B models) - 3-15 tok/s
| Model | Quant | Size | Tokens/sec |
|-------|-------|------|------------|
| Llama 3.3 70B | Q4_K_M | ~42GB | 8-12 |
| Qwen 2.5 72B | Q4_K_M | ~43GB | 7-10 |
| DeepSeek R1 70B | Q4_K_M | ~42GB | 7-10 |
| CodeLlama 70B | Q4_K_M | ~39GB | 7-10 |

### Massive Tier (100B+) - 1-10 tok/s
| Model | Quant | Size | Tokens/sec |
|-------|-------|------|------------|
| Qwen 3 235B Thinking | Q3_K | ~107GB | **8.3** (measured) |
| Qwen 3 235B | Q3_K_XL | ~98GB | 2-4 |
| Mistral Large 123B | Q3_K_L | ~61GB | 3-5 |
| Command R+ 104B | Q3_K_M | ~49GB | 4-6 |

## Recommended Software Stack

### llama.cpp (Best Performance)
```bash
# Build with ROCm support for Strix Halo
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151
cmake --build build --config Release -j

# Run with Vulkan (often faster on Strix Halo)
cmake -B build -DGGML_VULKAN=ON
cmake --build build --config Release -j
```

### LM Studio
- User-friendly GUI
- Works well on Strix Halo
- Automatic model management
- Download: https://lmstudio.ai

### Ollama
```bash
# Install Ollama
curl -fsSL https://ollama.com/install.sh | sh

# Run models (uses llama.cpp backend)
ollama run llama3.3:70b-instruct-q4_K_M
```

## Linux Configuration Tips

### 1. Maximize GTT Memory
```bash
# Check current GTT size
cat /sys/class/drm/card*/device/mem_info_gtt_total

# Set kernel parameter for maximum GTT
# Add to /etc/default/grub GRUB_CMDLINE_LINUX:
# amdgpu.gttsize=122880

# Then update grub
sudo update-grub
```

### 2. Kernel Version
Linux 6.15+ provides ~15% better performance on Strix Halo. Update if possible.

### 3. ROCm Installation
```bash
# Install ROCm 6.4+ for best gfx1151 support
# Follow official AMD instructions for your distro
```

### 4. rocWMMA for Better Performance
rocWMMA significantly improves matrix operations. Many pre-built containers include it:
- https://github.com/kyuz0/amd-strix-halo-toolboxes

## Model Selection Guide

### For Claude Code (Local LLM)

Recommended multi-model setup for running Claude Code with local models:

| Role | Model | Why |
|------|-------|-----|
| **Background** | llama-3.2-3b | Fast (68.8 tok/s), handles simple tasks like titles |
| **Default** | qwen2.5-coder-32b | Excellent coding ability, good context handling |
| **Reasoning** | deepseek-r1-32b | Strong reasoning, R1 architecture |

**Total memory: ~56GB** (leaves room for system + context)

Setup instructions: See [claude-code-router/README.md](claude-code-router/README.md)

### For General Chat
1. **Quick responses**: Qwen 2.5 7B or Llama 3.1 8B
2. **Best quality**: Llama 3.3 70B or Qwen 2.5 72B
3. **Balance**: Qwen 2.5 32B

### For Coding
1. **Fast**: DeepSeek Coder V2 16B (63.2 tok/s, MoE architecture)
2. **Best**: Qwen 2.5 Coder 32B (10.5 tok/s, excellent quality)
3. **Large context**: CodeLlama 70B

### For Reasoning/Math
1. DeepSeek R1 Distill 32B (best quality/speed, 10.5 tok/s)
2. Qwen 3 235B Thinking (maximum capability, 8.3 tok/s)
3. DeepSeek R1 Distill 70B (balance)

### For Vision Tasks
1. LLaVA 1.6 7B (fast)
2. Qwen 2.5 VL 7B (good quality)
3. Pixtral 12B (balance)

### For RAG/Tool Use
1. Command R+ 104B (Q3_K fits in memory)
2. Mistral Small 24B

## Context Length Considerations

With 128GB, you can run models with extended context:

| Model | Context | Memory Usage |
|-------|---------|--------------|
| 32B Q4 | 8K | ~22GB |
| 32B Q4 | 32K | ~28GB |
| 70B Q4 | 8K | ~45GB |
| 70B Q4 | 32K | ~55GB |
| Qwen 235B Q3 | 65K | ~110GB |
| Qwen 235B Q3 | 131K | ~122GB |

## Quantization Guide

| Quant | Quality Loss | Size Reduction | Recommended For |
|-------|--------------|----------------|-----------------|
| Q8_0 | Minimal | ~50% | Small models, max quality |
| Q6_K | Very low | ~60% | Models up to 32B |
| Q5_K_M | Low | ~65% | Models up to 70B |
| Q4_K_M | Acceptable | ~70% | 70B models |
| Q3_K | Noticeable | ~80% | 100B+ models |

## Troubleshooting

### Out of Memory
- Use lower quantization (Q4 → Q3)
- Reduce context length
- Close other applications

### Slow Performance
- Ensure GPU offloading is enabled (`-ngl 999`)
- Check kernel version (6.15+ recommended)
- Try Vulkan backend instead of ROCm

### Model Won't Load
- Check GTT size: `cat /sys/class/drm/card*/device/mem_info_gtt_total`
- Verify HIP/ROCm is detecting gfx1151
- Try running in a container with proper ROCm setup

## Resources

- [Strix Halo Homelab Wiki](https://strixhalo-homelab.d7.wtf/)
- [Framework Community Tests](https://community.frame.work/t/amd-strix-halo-ryzen-ai-max-395-gpu-llm-performance-tests/72521)
- [LHL's Strix Halo Testing](https://github.com/lhl/strix-halo-testing)
- [kyuz0's Toolboxes](https://github.com/kyuz0/amd-strix-halo-toolboxes)

## Total Storage Requirements

| Category | Approximate Size |
|----------|-----------------|
| Fast Models | ~25GB |
| Balanced Models | ~80GB |
| Large Models | ~130GB |
| Massive Models | ~160GB |
| Coding Models | ~80GB |
| Vision Models | ~35GB |
| Specialized | ~125GB |
| **Essential Pack** | **~150GB** |
| **Everything** | **~600GB+** |
