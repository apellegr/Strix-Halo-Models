# Strix Halo LLM Server

A comprehensive toolkit for running local LLM inference on AMD Ryzen AI Max+ 395 (Strix Halo) with 128GB unified memory. Includes server management, benchmarking, and optimization tools built around llama.cpp.

## Features

- **Dynamic Model Discovery** - Automatically detects models in the `models/` directory
- **Hybrid CPU+GPU Inference** - Optimized for Strix Halo's unified memory architecture
- **Benchmark & Optimize** - Find optimal GPU layer configurations for each model
- **Config Persistence** - Save and reuse optimized settings
- **OpenAI-Compatible API** - Works with Open WebUI, Continue, and other clients
- **Systemd Integration** - Auto-start models on boot

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
./install-llama-cpp.sh

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
# 1. List available models
./start-llm-server.sh list

# 2. Start a model
./start-llm-server.sh qwen3-235b-thinking

# 3. Check status
./start-llm-server.sh status

# 4. Test the API
curl http://localhost:8081/v1/models
```

## Downloading Models

The `download_strix_halo_models.sh` script downloads GGUF models optimized for Strix Halo's 128GB unified memory. It uses Hugging Face's fast transfer protocol for efficient downloads.

### Quick Download

```bash
# Make executable
chmod +x download_strix_halo_models.sh

# Download essential pack (best model per category, ~150GB)
./download_strix_halo_models.sh --essential

# Or run interactive menu
./download_strix_halo_models.sh
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
| `--specialized` | Various | ~125GB | RAG, MoE, etc. (Command R+, Mixtral) |
| `--essential` | Various | ~150GB | Best model per category |
| `--all` | All | ~600GB+ | Everything |

### Environment Variables

```bash
# Custom download directory (default: ~/llm-models)
MODELS_DIR=/mnt/nvme/models ./download_strix_halo_models.sh --essential

# Preview downloads without downloading
DRY_RUN=1 ./download_strix_halo_models.sh --all

# Disable fast HF transfer (if having issues)
ENABLE_HF_TRANSFER=0 ./download_strix_halo_models.sh --fast
```

### Notes

- Uses `huggingface_hub` with `hf_transfer` for fast downloads (auto-installs if missing)
- Skips files that already exist
- Supports multi-part models (automatically downloads all parts)
- Sources models from verified repos (bartowski, unsloth, TheBloke)
- See [MODELS.md](MODELS.md) for detailed model information and performance benchmarks

## Directory Structure

```
Strix-Halo-Models/
├── models/                    # Model files (auto-discovered)
│   ├── fast/                  # 3-9B models
│   ├── balanced/              # 14-32B models
│   ├── coding/                # Code-specialized models
│   ├── vision/                # Multimodal models
│   ├── specialized/           # Task-specific models
│   └── massive/               # 100B+ models
├── claude-code-router/        # Claude Code local LLM integration
│   ├── config.json            # Router configuration
│   ├── install.sh             # Router installation script
│   └── README.md              # Setup documentation
├── benchmarks/                # Benchmark results
├── start-llm-server.sh           # Server management script
├── start-claude-code-models.sh   # Start models for Claude Code
├── benchmark-model.sh            # Benchmarking tool
├── benchmark-all-models.sh       # Batch benchmark script
├── model-configs.json            # Optimized configurations
├── download_strix_halo_models.sh # Model downloader script
├── gpu-power-config.sh           # GPU power profile configuration
├── .env                          # Environment configuration
└── install-llama-cpp.sh          # llama.cpp installer
```

---

## Server Management

### Start a Model

```bash
# Start with auto-assigned port (finds next available starting from 8081)
./start-llm-server.sh qwen3-235b-thinking

# Start on a specific port
./start-llm-server.sh qwen2.5-7b 8082

# Start multiple models (each gets next available port automatically)
./start-llm-server.sh qwen3-235b-thinking  # Gets 8081
./start-llm-server.sh qwen2.5-7b           # Gets 8082
./start-llm-server.sh llama-3.1-8b         # Gets 8083
```

### Check Status

```bash
./start-llm-server.sh status
```

Output shows running models with optimization status:
```
MODEL                     PORT     STATUS             PID      MEMORY
-----                     ----     ------             ---      ------
qwen3-235b-thinking       8081     running (opt)      72852    51.0GB
qwen2.5-7b                8082     running            12345    5.2GB

Legend: running (opt) = optimized config, running = default config
```

### Stop Models

```bash
# Stop a specific model
./start-llm-server.sh stop qwen3-235b-thinking

# Stop all models
./start-llm-server.sh stop
```

### View Logs

```bash
./start-llm-server.sh logs qwen3-235b-thinking
```

### List Available Models

```bash
./start-llm-server.sh list
```

Shows all discovered models with their configurations:
```
NAME                      GPU_LAYERS CTX      SIZE     OPTIMIZED
----                      ---------- ---      ----     ---------
qwen2.5-7b                999        32768    5.1G
qwen3-235b-thinking       50         4096     47G      ✓
```

---

## Benchmarking

### Quick Benchmark

```bash
./benchmark-model.sh qwen2.5-7b
```

### Find Optimal Configuration

Automatically tests different GPU layer counts and saves the best config:

```bash
./benchmark-model.sh qwen3-235b-thinking --optimize
```

This will:
1. Test GPU layers: 20, 30, 40, 50, 60, 70, 80, 999
2. Find the configuration with best token generation speed
3. Save results to `model-configs.json`
4. Future server starts will use the optimized config

### GPU Layer Sweep

Test specific GPU layer configurations:

```bash
./benchmark-model.sh qwen3-235b --gpu-sweep
```

### Batch Size Sweep

Test different batch sizes:

```bash
./benchmark-model.sh qwen2.5-32b --batch-sweep
```

### Full Benchmark Suite

Run all benchmarks:

```bash
./benchmark-model.sh qwen2.5-7b --full
```

### Compare Models

```bash
./benchmark-model.sh --compare qwen2.5-7b llama-3.1-8b mistral-7b
```

### Benchmark All Models

```bash
./benchmark-all-models.sh
```

---

## Configuration

### Environment Variables (.env)

Copy and customize the `.env` file:

```bash
# Paths
MODELS_DIR="./models"              # Model files directory
RUN_DIR="$HOME/.llm-servers"       # PID and log files
RESULTS_DIR="./benchmarks"         # Benchmark results
CONFIG_FILE="./model-configs.json" # Optimized configs

# llama.cpp binaries
LLAMA_SERVER="$HOME/.local/bin/llama-server"
LLAMA_BENCH="$HOME/.local/bin/llama-bench"

# Server defaults
DEFAULT_PORT="8081"
DEFAULT_THREADS="16"
DEFAULT_BATCH_SIZE="512"
DEFAULT_CTX_SIZE="4096"
```

### Model Configurations (model-configs.json)

Optimized settings are stored in JSON format:

```json
{
  "models": {
    "llama-3.2-3b": {
      "gpu_layers": 50,
      "ctx_size": 8192,
      "batch_size": 1024,
      "benchmark": {
        "pp_tokens_per_sec": 2154.12,
        "tg_tokens_per_sec": 68.76,
        "memory_gb": 8
      }
    },
    "qwen2.5-coder-32b": {
      "gpu_layers": 80,
      "ctx_size": 32768,
      "batch_size": 1024,
      "benchmark": {
        "pp_tokens_per_sec": 316.83,
        "tg_tokens_per_sec": 10.52,
        "memory_gb": 24
      }
    }
  }
}
```

---

## Model Discovery

Models are automatically discovered from the `models/` directory structure:

```
models/<category>/<model-name>/<file>.gguf
models/<category>/<model-name>/<quantization>/<file>.gguf
```

### Default GPU Layers (based on model size)

| Total Size | GPU Layers | Mode |
|------------|------------|------|
| > 80 GB | 50 | Hybrid (CPU+GPU) |
| 40-80 GB | 60 | Hybrid (CPU+GPU) |
| < 40 GB | 999 | Full GPU offload |

### Adding New Models

Simply place GGUF files in the appropriate category folder:

```bash
# Example: Add a new 13B model
mkdir -p models/balanced/my-model-13b
cp my-model-13b-Q4_K_M.gguf models/balanced/my-model-13b/

# It will be automatically discovered
./start-llm-server.sh list
```

---

## Systemd Service

The included `llm-server@.service` template enables auto-start of models on boot.

### Install the Service

```bash
# Create systemd user directory if needed
mkdir -p ~/.config/systemd/user

# Copy the service template
cp llm-server@.service ~/.config/systemd/user/

# Reload systemd to recognize the new service
systemctl --user daemon-reload
```

### Customize Paths (if needed)

The service uses `%h` (home directory specifier). If your installation is not in `~/Strix-Halo-Models`, edit the service file:

```bash
nano ~/.config/systemd/user/llm-server@.service

# Update these lines to match your paths:
# WorkingDirectory=%h/your-path/Strix-Halo-Models
# ExecStart=%h/your-path/Strix-Halo-Models/start-llm-server.sh run %i
# ExecStop=%h/your-path/Strix-Halo-Models/start-llm-server.sh stop %i
```

### Enable and Start a Model

```bash
# Enable (auto-start on boot) and start immediately
systemctl --user enable --now llm-server@qwen3-235b-thinking

# Or separately:
systemctl --user enable llm-server@qwen3-235b-thinking
systemctl --user start llm-server@qwen3-235b-thinking
```

### Manage the Service

```bash
# Check status
systemctl --user status llm-server@qwen3-235b-thinking

# View logs (follow mode)
journalctl --user -u llm-server@qwen3-235b-thinking -f

# Stop the service
systemctl --user stop llm-server@qwen3-235b-thinking

# Disable auto-start
systemctl --user disable llm-server@qwen3-235b-thinking

# Restart after config changes
systemctl --user restart llm-server@qwen3-235b-thinking
```

### Enable Lingering (start without login)

By default, user services only run when you're logged in. Enable lingering to start services at boot:

```bash
loginctl enable-linger $USER
```

### Run Multiple Models

You can run multiple models as separate services - each will automatically get the next available port:

```bash
systemctl --user enable --now llm-server@qwen3-235b-thinking  # Gets port 8081
systemctl --user enable --now llm-server@qwen2.5-7b           # Gets port 8082
systemctl --user enable --now llm-server@llama-3.1-8b         # Gets port 8083
```

Check assigned ports with:
```bash
./start-llm-server.sh status
```

---

## Open WebUI Integration

Connect Open WebUI to your local models:

1. **Start a model:**
   ```bash
   ./start-llm-server.sh qwen3-235b-thinking
   ```

2. **Configure Open WebUI:**
   - Go to Settings → Connections → OpenAI API
   - URL: `http://localhost:8081/v1`
   - API Key: `sk-dummy` (any value works)

3. **Select the model** in the chat interface

---

## GPU Memory Settings

Critical environment variables for Strix Halo unified memory (automatically set by scripts):

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

### Unified Memory Architecture

Strix Halo uses unified memory where CPU and GPU share the same 128GB RAM pool. This enables running very large models but has implications for running multiple models:

- **Single large model**: Can use up to ~115GB for model + context
- **Multiple models**: GPU memory allocation may fail even with RAM available
- The script automatically warns when starting a second model

### Memory Warnings

When starting a model while another is running, you'll see:

```
[WARN] Concurrent Model Warning
  Another model is already running using ~51GB
  Running multiple GPU-accelerated models simultaneously
  may cause memory allocation failures on unified memory APUs.

  If this model fails to load, try:
    - Stop other models first: ./start-llm-server.sh stop
    - Use smaller context: reduces KV cache memory
    - Use fewer GPU layers: offload to CPU instead
```

### Running Multiple Models

To run multiple models simultaneously:

1. **Use smaller models** - 7B models use ~6-8GB each
2. **Reduce context size** - Lower context = smaller KV cache
3. **Use CPU offload** - Set `gpu_layers` lower than 999 in `model-configs.json`

Example for running two models:
```bash
# First model (large, optimized)
./start-llm-server.sh qwen3-235b-thinking  # Uses ~51GB, port 8081

# Second model would need to use remaining memory
# May fail with full GPU offload - consider CPU-only for second model
```

### Memory Estimation

The script estimates memory needs based on:
- Model file size (including all parts for split models)
- Context size (KV cache scales with context)
- Compute buffer overhead (~10-20% of model size)

---

## Performance Tips

### Optimal Thread Count

Use physical cores only (not SMT threads):
```bash
# Strix Halo has 16 physical cores
DEFAULT_THREADS=16
```

### Memory Mapping

Disable mmap for better performance with large models:
```bash
# Already enabled by default in scripts
--no-mmap
```

### Context Size

Reduce context for memory-constrained scenarios:
- Large models (>80GB): Use 4096 context
- Medium models (40-80GB): Use 8192 context
- Small models (<40GB): Use 16384-32768 context

---

## Troubleshooting

### Model Won't Start (OOM)

```bash
# Run optimization to find working GPU layers
./benchmark-model.sh <model-name> --optimize

# Or manually reduce GPU layers
# Edit model-configs.json or use lower default
```

### Status Shows "stopped" for Running Model

```bash
# Check if llama-server is actually running
pgrep -a llama-server

# Verify PID file matches
cat ~/.llm-servers/<model-name>.pid
```

### Slow Performance

1. Check GPU layers are being used:
   ```bash
   ./start-llm-server.sh logs <model-name> | grep "offload"
   ```

2. Verify ROCm is detecting the GPU:
   ```bash
   rocm-smi
   ```

3. Run benchmark to find optimal config:
   ```bash
   ./benchmark-model.sh <model-name> --optimize
   ```

### "Unknown model" Error

Ensure model is in the correct directory structure:
```bash
# Check if model is discovered
./start-llm-server.sh list | grep <model-name>

# Verify file exists
ls models/*/<model-name>/
```

---

## API Examples

### List Models

```bash
curl http://localhost:8081/v1/models
```

### Chat Completion

```bash
curl http://localhost:8081/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{
    "model": "qwen3-235b-thinking",
    "messages": [{"role": "user", "content": "Hello!"}]
  }'
```

### Health Check

```bash
curl http://localhost:8081/health
```

---

## Claude Code Integration

Run Claude Code with local LLM models using the Claude Code Router.

### Quick Setup

```bash
# 1. Install the router
./claude-code-router/install.sh

# 2. Start models and router
./start-claude-code-models.sh all

# 3. Use Claude Code with local models
export ANTHROPIC_BASE_URL=http://localhost:3456
claude
```

### Model Configuration

The router maps different Claude Code task types to specialized local models:

| Task Type | Model | Port | Speed |
|-----------|-------|------|-------|
| Background (titles, topics) | llama-3.2-3b | 8081 | 68.8 tok/s |
| Default (main coding) | qwen2.5-coder-32b | 8082 | 10.5 tok/s |
| Think (reasoning) | deepseek-r1-32b | 8083 | 10.5 tok/s |

### Management Commands

```bash
# Start all Claude Code models
./start-claude-code-models.sh

# Start models and router
./start-claude-code-models.sh all

# Check status
./start-claude-code-models.sh status

# Stop all
./start-claude-code-models.sh stop
```

See [claude-code-router/README.md](claude-code-router/README.md) for detailed setup instructions.

---

## GPU Power Configuration

Optimize GPU performance with power profile settings:

```bash
# Check current power profile
cat /sys/class/drm/card*/device/power_dpm_force_performance_level

# Set to high performance (requires root)
sudo ./gpu-power-config.sh performance

# Available profiles: auto, low, high, performance
```

For persistent settings, see `gpu-power-config.sh`.

---

## Server Optimizations

The server scripts include several performance optimizations:

### Flash Attention
Enabled by default for faster attention computation:
```bash
--flash-attn on
```

### Parallel Slots
Controls concurrent request handling. Default is 1 for dedicated processing:
```bash
--parallel 1  # Single slot (faster individual requests)
--parallel 4  # Multiple slots (better throughput)
```

### Batch Size
Larger batch size improves prompt processing speed:
```bash
--batch-size 1024  # Default (increased from 512)
```

### Custom Context Size
Override context size per model:
```bash
./start-llm-server.sh qwen2.5-coder-32b -c 32768
./start-llm-server.sh llama-3.2-3b -c 8192
```

---

## Resources

- [MODELS.md](MODELS.md) - Detailed model information and performance expectations
- [claude-code-router/README.md](claude-code-router/README.md) - Claude Code local LLM setup
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - Inference engine
- [Strix Halo Homelab Wiki](https://strixhalo-homelab.d7.wtf/) - Community resources
- [Open WebUI](https://github.com/open-webui/open-webui) - Web interface

## License

MIT License - See LICENSE file for details.
