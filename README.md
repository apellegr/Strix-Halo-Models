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
├── benchmarks/                # Benchmark results
├── start-llm-server.sh        # Server management script
├── benchmark-model.sh         # Benchmarking tool
├── benchmark-all-models.sh    # Batch benchmark script
├── model-configs.json         # Optimized configurations
├── .env                       # Environment configuration
└── install-llama-cpp.sh       # llama.cpp installer
```

---

## Server Management

### Start a Model

```bash
# Start with default settings
./start-llm-server.sh qwen3-235b-thinking

# Start on a specific port
./start-llm-server.sh qwen2.5-7b 8082

# Start multiple models on different ports
./start-llm-server.sh qwen2.5-7b 8082
./start-llm-server.sh llama-3.1-8b 8083
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
    "qwen3-235b-thinking": {
      "gpu_layers": 50,
      "ctx_size": 4096,
      "batch_size": 512,
      "benchmark": {
        "pp_tokens_per_sec": 129.25,
        "tg_tokens_per_sec": 8.33,
        "memory_gb": 51
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

You can run multiple models as separate services:

```bash
systemctl --user enable --now llm-server@qwen3-235b-thinking
systemctl --user enable --now llm-server@qwen2.5-7b
systemctl --user enable --now llm-server@llama-3.1-8b
```

**Note:** Each model uses the default port (8081). To run multiple models simultaneously, you'll need to modify the service or script to use different ports.

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

## Resources

- [MODELS.md](MODELS.md) - Detailed model information and performance expectations
- [llama.cpp](https://github.com/ggerganov/llama.cpp) - Inference engine
- [Strix Halo Homelab Wiki](https://strixhalo-homelab.d7.wtf/) - Community resources
- [Open WebUI](https://github.com/open-webui/open-webui) - Web interface

## License

MIT License - See LICENSE file for details.
