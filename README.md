# Strix Halo LLM Server

A comprehensive toolkit for running local LLM inference on AMD Ryzen AI Max+ 395 (Strix Halo) with 128GB unified memory. Includes server management, benchmarking, GPU memory optimization, and quick-start scripts built around llama.cpp.

## Highlights

- Run **235B-parameter models** locally on a single chip with 128GB unified memory
- **70 tok/s generation** on Qwen3 Coder 30B MoE, **51 tok/s** on GPT-OSS 120B
- Hybrid CPU+GPU inference optimized for Strix Halo's unified memory architecture
- OpenAI-compatible API that works with Open WebUI, Continue, Claude Code, and other clients
- Pre-tuned configurations for 38 models with benchmark data

## Benchmarks

Measured on AMD Ryzen AI Max+ 395, 128GB LPDDR5X, ROCm 7.2, llama.cpp (Lychee b8182). All models fully GPU offloaded (ngl=999) except Qwen3-235B (80/95 layers).

| Model | Params | Quant | Prompt (tok/s) | Generation (tok/s) | Size |
|-------|--------|-------|----------------|-------------------|------|
| **Qwen3 Coder 30B** | 30B MoE (3B active) | Q4_K_M | 812 | **69.6** | 17 GB |
| **Llama 3.2 3B** | 3B | Q6_K | 1,538 | **69.0** | 3 GB |
| **DeepSeek Coder V2 16B** | 16B MoE | Q5_K_M | 1,227 | **68.0** | 11 GB |
| **GLM-4.7 Flash** | MoE | Q4_K_M | 897 | **54.1** | 17 GB |
| **GPT-OSS 120B** | 120B | MXFP4 | 174 | **51.1** | 59 GB |
| **Llama 4 Scout** | 109B MoE (17B-16E) | Q4_K_M | 282 | **19.2** | 61 GB |
| **Qwen 3.5 122B-A10B** | 122B MoE (10B active) | MXFP4 | 136 | **18.3** | 70 GB |
| **Qwen 2.5 Coder 32B** | 32B | Q4_K_M | 264 | **11.0** | 19 GB |
| **DeepSeek R1 32B** | 32B | Q4_K_M | 255 | **11.0** | 19 GB |
| **Qwen3-235B Thinking** | 235B MoE (22B active) | Q3_K_M | 135 | **7.8** | 105 GB |
| **Llama 3.3 70B** | 70B | Q6_K | 86 | **3.8** | 54 GB |

MoE models achieve 3-14x higher TG than similarly-sized dense models by only activating a fraction of parameters per token. The system is **memory-bandwidth bound** (~85 GB/s host-to-device). See [docs/MODELS.md](docs/MODELS.md) for the full model guide and all 38 benchmarked models.

## Hardware Requirements

| Component | Specification |
|-----------|--------------|
| CPU | AMD Ryzen AI Max+ 395 (16 Zen 5 cores) |
| GPU | Radeon 8060S (40 RDNA 3.5 CUs) |
| Memory | 128GB LPDDR5X unified memory |
| Storage | 500GB+ for model files |

## Prerequisites

1. **ROCm 6.4+** with HIP support
2. **llama.cpp** compiled with ROCm/HIP backend
3. **jq** for JSON processing

### Install llama.cpp

```bash
# Use the included installation script
./scripts/setup/install-llama-cpp.sh

# Or build manually with ROCm support
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DGGML_HIP=ON -DAMDGPU_TARGETS=gfx1151
cmake --build build --config Release -j$(nproc)

# Install binaries
cp build/bin/llama-* ~/.local/bin/
```

## Quick Start

```bash
# 1. Copy and edit environment config
cp .env.example .env

# 2. Download models
./scripts/setup/download_strix_halo_models.sh --essential

# 3. Start a model (using the server manager)
./scripts/server/start-llm-server.sh qwen3-235b-thinking

# 4. Or use a quick-start script directly
./scripts/server/start-qwen3-235b.sh

# 5. Test the API
curl http://localhost:8081/v1/models
```

### Quick-Start Scripts

Pre-configured scripts for popular models. Set `MODELS_DIR`, `LLAMA_SERVER`, and `PORT` in `.env` or as environment variables:

| Script | Model | Generation | Memory |
|--------|-------|-----------|--------|
| `scripts/server/start-qwen3-235b.sh` | Qwen3-235B Thinking (Q3_K_M) | 7.8 tok/s | ~105 GB |
| `scripts/server/start-qwen35-122b.sh` | Qwen 3.5 122B-A10B (MXFP4) | 18.3 tok/s | ~70 GB |
| `scripts/server/start-gpt-oss-120b.sh` | GPT-OSS 120B (MXFP4) | 51.1 tok/s | ~59 GB |
| `scripts/server/start-coder-32b.sh` | Qwen 2.5 Coder 32B (Q4_K_M) | 11.0 tok/s | ~19 GB |

## Downloading Models

```bash
# Download essential pack (best model per category, ~150GB)
./scripts/setup/download_strix_halo_models.sh --essential

# Or run interactive menu
./scripts/setup/download_strix_halo_models.sh

# Preview downloads without downloading
DRY_RUN=1 ./scripts/setup/download_strix_halo_models.sh --all

# Custom download directory
MODELS_DIR=/mnt/nvme/models ./scripts/setup/download_strix_halo_models.sh --essential
```

### Available Categories

| Category | Size Range | Storage | Description |
|----------|------------|---------|-------------|
| `--fast` | 3-9B | ~25GB | Quick responses (Llama 3.2, Qwen 2.5 7B, etc.) |
| `--balanced` | 14-32B | ~80GB | Quality/speed balance (Qwen 32B, DeepSeek R1 32B) |
| `--large` | 70B | ~130GB | High capability (Llama 3.3 70B, Qwen 72B) |
| `--massive` | 100B+ | ~220GB | Frontier models (Qwen 3 235B, GPT-OSS 120B) |
| `--coding` | Various | ~80GB | Programming optimized (Qwen Coder, DeepSeek) |
| `--vision` | Various | ~20GB | Multimodal (LLaVA, Qwen VL, Pixtral) |
| `--essential` | Various | ~150GB | Best model per category |
| `--all` | All | ~600GB+ | Everything |

## Directory Structure

```
Strix-Halo-Models/
├── model-configs.json              # Optimized configurations (28+ models)
├── llm-server@.service             # Systemd service template
├── .env.example                    # Environment config template
├── .env                            # Your local config (not committed)
├── docs/                           # Documentation
│   ├── MODELS.md                   # Model selection guide & benchmarks
│   ├── RATE-LIMITING.md            # Rate limiting for GPU stability
│   └── ROCM-MEMORY-LIMIT-INVESTIGATION.md
├── claude-code-router/             # Claude Code local LLM integration
├── benchmarks/                     # Benchmark results and tools
│   └── bandwidth/                  # Memory bandwidth benchmarks
└── scripts/
    ├── server/                     # Server start/stop/management
    │   ├── start-llm-server.sh     # Main server management script
    │   ├── llm-server-manager.sh   # Multi-model server manager
    │   ├── start-qwen35-122b.sh    # Quick-start: Qwen 3.5 122B-A10B
    │   ├── start-qwen3-235b.sh     # Quick-start: Qwen3 235B Thinking
    │   ├── start-gpt-oss-120b.sh   # Quick-start: GPT-OSS 120B
    │   ├── start-coder-32b.sh      # Quick-start: Qwen 2.5 Coder 32B
    │   ├── start-claude-code-models.sh # Start models for Claude Code
    │   ├── start-llm-with-rate-limit.sh # Server + rate limiting proxy
    │   └── llm-rate-limiter.py     # Rate limiting HTTP proxy
    ├── benchmarks/                  # Performance testing
    │   ├── benchmark-model.sh      # Benchmarking tool
    │   ├── benchmark-all-models.sh # Batch benchmark script
    │   └── batch-size-sweep.sh     # Batch size optimization
    ├── gpu/                         # GPU control & verification
    │   ├── gpu-power.sh            # GPU power/performance control
    │   ├── gpu-max-power.sh        # Quick max power script
    │   ├── gpu-monitor.sh          # Real-time GPU monitoring
    │   └── verify-gpu-memory.sh    # Memory config verification
    ├── testing/                     # Stress & crash testing
    │   ├── stress-test.sh          # Load testing suite
    │   └── crash-catcher.sh        # GPU crash monitoring
    ├── monitoring/                  # System & metrics
    │   ├── system-status.sh        # System status dashboard
    │   ├── amd-gpu-metrics.sh      # GPU metrics collection
    │   └── rapl-power-metrics.sh   # CPU power metrics
    └── setup/                       # Installation & download
        ├── install-llama-cpp.sh    # llama.cpp installer
        └── download_strix_halo_models.sh # Model downloader
```

---

## Server Management

### Start a Model

```bash
# Start with auto-assigned port (finds next available starting from 8081)
./scripts/server/start-llm-server.sh qwen3-235b-thinking

# Start on a specific port
./scripts/server/start-llm-server.sh qwen2.5-7b 8082

# Start multiple models
./scripts/server/start-llm-server.sh qwen3-235b-thinking  # Gets 8081
./scripts/server/start-llm-server.sh qwen2.5-7b           # Gets 8082
```

### Check Status

```bash
./scripts/server/start-llm-server.sh status
```

### Stop / Logs / List

```bash
./scripts/server/start-llm-server.sh stop qwen3-235b-thinking  # Stop specific model
./scripts/server/start-llm-server.sh stop                       # Stop all
./scripts/server/start-llm-server.sh logs qwen3-235b-thinking   # View logs
./scripts/server/start-llm-server.sh list                       # List available models
```

---

## Benchmarking

```bash
# Quick benchmark
./scripts/benchmarks/benchmark-model.sh qwen2.5-7b

# Find optimal GPU layers + batch size and save to model-configs.json
./scripts/benchmarks/benchmark-model.sh qwen3-235b-thinking --optimize

# GPU layer sweep
./scripts/benchmarks/benchmark-model.sh qwen3-235b --gpu-sweep

# Batch size sweep
./scripts/benchmarks/benchmark-model.sh qwen2.5-32b --batch-sweep

# Compare models
./scripts/benchmarks/benchmark-model.sh --compare qwen2.5-7b llama-3.1-8b mistral-7b

# Benchmark all models
./scripts/benchmarks/benchmark-all-models.sh
```

---

## Configuration

### Environment Variables

Copy `.env.example` to `.env` and customize:

```bash
cp .env.example .env
```

Key variables:

```bash
MODELS_DIR="$HOME/llm-models"                  # Model files directory
LLAMA_SERVER="$HOME/.local/bin/llama-server"    # llama-server binary
DEFAULT_PORT="8081"                             # Default server port
DEFAULT_THREADS="16"                            # CPU threads (physical cores)
```

See `.env.example` for the full list with descriptions.

### Model Configurations (model-configs.json)

Optimized settings for 28+ models, including benchmark data:

```json
{
  "qwen3-235b-thinking": {
    "gpu_layers": 80,
    "ctx_size": 16384,
    "batch_size": 256,
    "benchmark": {
      "pp_tokens_per_sec": 85.8,
      "tg_tokens_per_sec": 12.8,
      "memory_gpu_gb": 87.5
    }
  }
}
```

---

## GPU Memory Settings

### ROCm Memory Limit Fix

By default, ROCm limits GPU memory to ~61GB on Strix Halo APUs. To unlock the full 90GB+, add these kernel parameters to `/etc/default/grub`:

```bash
GRUB_CMDLINE_LINUX_DEFAULT="... ttm.pages_limit=24576000 amdgpu.no_system_mem_limit=1 amdgpu.gttsize=117760"
```

Then run `sudo update-grub && sudo reboot`.

Use `--no-mmap` with llama-server (already enabled in all scripts) to avoid mmap/SVM interaction issues.

**Results after fix:**

| Metric | Before | After |
|--------|--------|-------|
| Max GPU Memory | 61 GB | 90 GB |
| Max GPU Layers (Qwen3-235B) | 55 | 81 |
| Prompt Speed | 37 tok/s | 546 tok/s |

See [docs/ROCM-MEMORY-LIMIT-INVESTIGATION.md](docs/ROCM-MEMORY-LIMIT-INVESTIGATION.md) for the full investigation.

### ROCm Environment Variables

Critical for Strix Halo unified memory (automatically set by all scripts):

```bash
export HSA_ENABLE_SDMA=0
export GPU_MAX_HEAP_SIZE=100
export GPU_MAX_ALLOC_PERCENT=100
export GPU_SINGLE_ALLOC_PERCENT=100
export GPU_FORCE_64BIT_PTR=1
export HIP_VISIBLE_DEVICES=0
export HSA_OVERRIDE_GFX_VERSION=11.5.1
```

---

## Memory Management

Strix Halo uses unified memory where CPU and GPU share the same 128GB RAM pool:

- **Single large model**: Can use up to ~115GB for model + context
- **Multiple models**: GPU memory allocation may fail even with RAM available
- The script automatically warns when starting a second model

### Memory Estimation by Model Size

| Model Size | Typical GPU Layers | Memory Usage |
|------------|-------------------|--------------|
| 3-9B (Q5-Q6) | 999 (full GPU) | 3-7 GB |
| 14-32B (Q4-Q5) | 999 (full GPU) | 10-19 GB |
| 70B (Q4) | 999 (full GPU) | 40-55 GB |
| 120-235B (Q3/MXFP4) | 80-999 | 59-105 GB |

---

## Systemd Service

Auto-start models on boot with the included service template:

```bash
# Install
mkdir -p ~/.config/systemd/user
cp llm-server@.service ~/.config/systemd/user/
systemctl --user daemon-reload

# Enable and start
systemctl --user enable --now llm-server@qwen3-235b-thinking

# Enable lingering (start without login)
loginctl enable-linger $USER
```

---

## Open WebUI Integration

```bash
# 1. Start a model
./scripts/server/start-llm-server.sh qwen3-235b-thinking

# 2. In Open WebUI: Settings -> Connections -> OpenAI API
#    URL: http://localhost:8081/v1
#    API Key: sk-dummy (any value works)
```

---

## Claude Code Integration

Run Claude Code with local LLM models using the Claude Code Router:

```bash
# 1. Install the router
./claude-code-router/install.sh

# 2. Start models and router
./scripts/server/start-claude-code-models.sh all

# 3. Use Claude Code with local models
export ANTHROPIC_BASE_URL=http://localhost:3456
claude
```

See [claude-code-router/README.md](claude-code-router/README.md) for detailed setup.

---

## API Examples

```bash
# List models
curl http://localhost:8081/v1/models

# Chat completion
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-235b-thinking",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'

# Health check
curl http://localhost:8081/health
```

---

## Memory Bandwidth Benchmarks

The `benchmarks/bandwidth/` directory contains tools to measure memory bandwidth:

| Test | Bandwidth | Notes |
|------|-----------|-------|
| CPU STREAM (Triad) | 112 GB/s | DDR5 system memory |
| GPU Internal (4GB) | 236 GB/s | Infinity Cache benefit |
| GPU Internal (20GB) | 205 GB/s | Beyond cache size |
| Host-to-Device | 85 GB/s | LLM inference bottleneck |
| Device-to-Host | 82 GB/s | Actual data movement |

---

## Troubleshooting

### Model Won't Start (OOM)
```bash
./scripts/benchmarks/benchmark-model.sh <model-name> --optimize  # Find working GPU layers
```

### Slow Performance
1. Check GPU offload: `./scripts/server/start-llm-server.sh logs <model-name> | grep "offload"`
2. Verify ROCm: `rocm-smi`
3. Re-optimize: `./scripts/benchmarks/benchmark-model.sh <model-name> --optimize`

### GPU Crashes Under Load
See [docs/RATE-LIMITING.md](docs/RATE-LIMITING.md) for the rate-limiting solution to MES scheduler crashes.

---

## Resources

- [docs/MODELS.md](docs/MODELS.md) - Detailed model guide and performance expectations
- [docs/ROCM-MEMORY-LIMIT-INVESTIGATION.md](docs/ROCM-MEMORY-LIMIT-INVESTIGATION.md) - GPU memory limit deep-dive
- [docs/RATE-LIMITING.md](docs/RATE-LIMITING.md) - Rate limiting for GPU stability
- [claude-code-router/README.md](claude-code-router/README.md) - Claude Code local LLM setup
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - Inference engine
- [Strix Halo Homelab Wiki](https://strixhalo-homelab.d7.wtf/) - Community resources
- [Open WebUI](https://github.com/open-webui/open-webui) - Web interface

## License

MIT License - See LICENSE file for details.
