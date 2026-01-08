# Claude Code Router Configuration

This guide explains how to run Claude Code with local LLM models using llama.cpp and the claude-code-router.

## Overview

The setup routes Claude Code API requests to local llama.cpp servers running different models optimized for specific tasks:

| Port | Model | Role | Context | GPU Layers |
|------|-------|------|---------|------------|
| 8081 | llama-3.2-3b | Background tasks (titles, summaries) | 8K | 50 |
| 8082 | hermes-4-14b | Default coding tasks | 32K | 80 |
| 8083 | hermes-4-70b | Complex reasoning | 64K | 40 |

The **claude-code-router** (port 3456) sits in front of these servers and routes requests based on the task type.

## Prerequisites

- AMD Strix Halo system with 128GB unified memory (or similar)
- llama.cpp compiled with ROCm support
- Node.js (for claude-code-router)
- Claude Code CLI installed

### Install claude-code-router

```bash
npm install -g @anthropic/claude-code
npm install -g @musistudio/claude-code-router
```

### Download Models

```bash
cd ~/Strix-Halo-Models
./download_strix_halo_models.sh
```

This downloads the required GGUF models to the `models/` directory.

## Quick Start

### 1. Start All Models and Router

```bash
cd ~/Strix-Halo-Models
./start-claude-code-models.sh all
```

This starts:
- llama-3.2-3b on port 8081
- hermes-4-14b on port 8082
- hermes-4-70b on port 8083
- claude-code-router on port 3456

### 2. Run Claude Code

```bash
export ANTHROPIC_BASE_URL=http://localhost:3456
claude
```

Or add to your `.bashrc` for persistence:

```bash
echo 'export ANTHROPIC_BASE_URL=http://localhost:3456' >> ~/.bashrc
source ~/.bashrc
```

## Scripts Reference

### start-claude-code-models.sh

Main script to manage the Claude Code model stack.

```bash
./start-claude-code-models.sh          # Start all models
./start-claude-code-models.sh stop     # Stop all models
./start-claude-code-models.sh status   # Check status
./start-claude-code-models.sh router   # Start router only
./start-claude-code-models.sh all      # Start models + router
```

### start-llm-server.sh

Low-level script to start individual llama.cpp servers.

```bash
./start-llm-server.sh <model-name> [port]    # Start a model
./start-llm-server.sh status                  # Show all running models
./start-llm-server.sh stop                    # Stop all models
./start-llm-server.sh list                    # List available models
```

Examples:
```bash
./start-llm-server.sh hermes-4-14b 8082
./start-llm-server.sh qwen2.5-coder-32b 8084
```

## Configuration Files

### model-configs.json

Defines optimized settings for each model:

```json
{
  "hermes-4-70b": {
    "gpu_layers": 40,
    "ctx_size": 65536,
    "batch_size": 2048,
    "notes": "Reduced GPU layers to avoid VRAM OOM when running with other models."
  }
}
```

Key parameters:
- `gpu_layers` - Number of layers to offload to GPU (lower = more CPU, less VRAM)
- `ctx_size` - Maximum context window size
- `batch_size` - Tokens processed per batch (higher = faster prompt processing)

### claude-code-router/config.json

Router configuration that maps task types to providers:

```json
{
  "Providers": [
    {
      "name": "local-fast",
      "api_base_url": "http://localhost:8081/v1/chat/completions",
      "models": ["llama-3.2-3b"]
    },
    {
      "name": "local-coder",
      "api_base_url": "http://localhost:8082/v1/chat/completions",
      "models": ["hermes-4-14b"]
    },
    {
      "name": "local-reasoning",
      "api_base_url": "http://localhost:8083/v1/chat/completions",
      "models": ["hermes-4-70b"]
    }
  ],
  "Router": {
    "background": "local-fast,llama-3.2-3b",
    "default": "local-coder,hermes-4-14b",
    "think": "local-reasoning,hermes-4-70b",
    "longContext": "local-coder,hermes-4-14b",
    "longContextThreshold": 60000,
    "webSearch": "local-fast,llama-3.2-3b",
    "image": "local-coder,hermes-4-14b"
  }
}
```

The router config is stored at `~/.claude-code-router/config.json`. Copy from this repo:

```bash
cp claude-code-router/config.json ~/.claude-code-router/config.json
```

## Router Task Types

| Task Type | Description | Recommended Model |
|-----------|-------------|-------------------|
| `background` | Titles, summaries, quick tasks | Small, fast model (3B) |
| `default` | General coding, file edits | Medium model with tool support (14B) |
| `think` | Complex reasoning, planning | Large model (70B) |
| `longContext` | Requests > longContextThreshold | Model with large context |
| `webSearch` | Web search queries | Fast model |
| `image` | Image analysis | Vision-capable model |

## Troubleshooting

### Context Size Errors

```
request (37245 tokens) exceeds the available context size (32768 tokens)
```

**Solution:** Increase `ctx_size` in `model-configs.json` and restart the model:

```bash
# Edit model-configs.json, then:
./start-llm-server.sh stop
./start-claude-code-models.sh
```

### Out of Memory (OOM) Errors

```
cudaMalloc failed: out of memory
```

**Solution:** Reduce `gpu_layers` for the model. For 70B models on 128GB systems, 40 GPU layers works well when running multiple models.

### 503 "Loading Model" Errors

This usually means the server is busy processing a request (not actually loading).

**Solutions:**
- Wait for current request to complete
- Increase `batch_size` for faster prompt processing
- Use a smaller model for the task type

### Slow Prompt Processing

Large prompts take time, especially on 70B models with reduced GPU layers.

**Solutions:**
- Increase `batch_size` (e.g., 2048)
- Route long-context requests to a faster model
- Use the 14B model for most tasks, reserve 70B for complex reasoning

## Memory Usage

Approximate memory usage for the default configuration:

| Model | Model Size | KV Cache (64K ctx) | Total |
|-------|------------|-------------------|-------|
| llama-3.2-3b | ~2GB | ~0.5GB | ~3GB |
| hermes-4-14b | ~10GB | ~4GB | ~14GB |
| hermes-4-70b | ~42GB | ~10GB | ~52GB |
| **Total** | | | **~70GB** |

This leaves ~50GB free on a 128GB system for other applications.

## Customization

### Using Different Models

Edit `start-claude-code-models.sh` to change which models are started:

```bash
CLAUDE_CODE_MODELS=(
    "llama-3.2-3b:8081:background"
    "qwen2.5-coder-32b:8082:default"      # Use Qwen instead of Hermes
    "deepseek-r1-32b:8083:reasoning"       # Use DeepSeek for reasoning
)
```

Then update `~/.claude-code-router/config.json` to match.

### Adding New Models

1. Add model config to `model-configs.json`
2. Download the model with `download_strix_halo_models.sh` or manually
3. Start with `./start-llm-server.sh <model-name> <port>`

## Logs

Server logs are stored in `~/.llm-servers/`:

```bash
tail -f ~/.llm-servers/hermes-4-70b.log    # Watch model logs
tail -f /tmp/ccr.log                        # Watch router logs
```

## System Status

Use the system status script to monitor everything:

```bash
./system-status.sh         # Snapshot
./system-status.sh -w      # Watch mode
```
