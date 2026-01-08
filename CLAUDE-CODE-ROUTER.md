# Claude Code Router Configuration

This guide explains how to run Claude Code with local LLM models using llama.cpp and the claude-code-router.

## Overview

The setup routes Claude Code API requests to local llama.cpp servers running different models optimized for specific tasks:

| Port | Model | Role | Context | GPU Layers | Speed |
|------|-------|------|---------|------------|-------|
| 8081 | llama-3.2-3b | Background tasks | 32K | 50 | ~50 tok/s |
| 8082 | hermes-4-14b | Default coding | 32K | 80 | ~20 tok/s |
| 8083 | hermes-4-70b | Complex reasoning | 64K | 50 | ~3.4 tok/s |

The **claude-code-router** (port 3456) sits in front of these servers and routes requests based on the task type.

## Prerequisites

- AMD Strix Halo system with 128GB unified memory (or similar)
- llama.cpp compiled with ROCm support
- Node.js (for claude-code-router)
- Claude Code CLI installed

### Install claude-code-router

```bash
npm install -g @anthropic-ai/claude-code
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

### 2. Install the Transformer Plugin

Copy the transformer plugin to enable proper responses from Hermes models:

```bash
mkdir -p ~/.claude-code-router/plugins
cp claude-code-router/hermes-direct.js ~/.claude-code-router/plugins/
cp claude-code-router/config.json ~/.claude-code-router/config.json
```

### 3. Run Claude Code

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
  "llama-3.2-3b": {
    "gpu_layers": 50,
    "ctx_size": 32768,
    "batch_size": 2048
  },
  "hermes-4-14b": {
    "gpu_layers": 80,
    "ctx_size": 32768,
    "batch_size": 1024
  },
  "hermes-4-70b": {
    "gpu_layers": 50,
    "ctx_size": 65536,
    "batch_size": 2048,
    "notes": "50 GPU layers balances speed vs memory for multi-model setup"
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
      "models": ["llama-3.2-3b"],
      "transformer": { "use": [] }
    },
    {
      "name": "local-coder",
      "api_base_url": "http://localhost:8082/v1/chat/completions",
      "models": ["hermes-4-14b"],
      "transformer": { "use": [] }
    },
    {
      "name": "local-reasoning",
      "api_base_url": "http://localhost:8083/v1/chat/completions",
      "models": ["hermes-4-70b"],
      "transformer": { "use": ["hermes-direct"] }
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

## Transformer Plugins

### hermes-direct.js

The `hermes-direct` transformer solves an issue where Hermes 4 70B outputs internal monologue (text prefixed with asterisks like `*Hmm...`) instead of direct responses.

**What it does:**
1. Injects a system prompt instructing the model to respond directly
2. Strips any remaining thinking patterns from responses

**Installation:**
```bash
cp claude-code-router/hermes-direct.js ~/.claude-code-router/plugins/
```

The transformer is enabled in the router config for the `local-reasoning` provider.

## Router Task Types

| Task Type | Description | Model | Speed |
|-----------|-------------|-------|-------|
| `background` | Titles, summaries, quick tasks | llama-3.2-3b | ~50 tok/s |
| `default` | General coding, file edits | hermes-4-14b | ~20 tok/s |
| `think` | Complex reasoning, planning | hermes-4-70b | ~3.4 tok/s |
| `longContext` | Requests > 60K tokens | hermes-4-14b | ~20 tok/s |
| `webSearch` | Web search queries | llama-3.2-3b | ~50 tok/s |
| `image` | Image analysis | hermes-4-14b | ~20 tok/s |

## Troubleshooting

### Empty Output from hermes-4-70b

If hermes-4-70b returns empty responses, ensure the `hermes-direct` transformer is installed:

```bash
# Check if plugin exists
ls ~/.claude-code-router/plugins/hermes-direct.js

# If missing, copy it
cp claude-code-router/hermes-direct.js ~/.claude-code-router/plugins/

# Restart the router
pkill -f claude-code-router
ccr start &
```

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

**Solution:** Reduce `gpu_layers` for the model. For 70B models on 128GB systems:
- 50 GPU layers works well when running 3 models simultaneously
- 60+ layers may cause OOM with large context windows

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

## Performance Benchmarks

Tested on AMD Ryzen AI Max+ 395 with 128GB unified memory:

| Model | Prompt Processing | Generation | Memory |
|-------|-------------------|------------|--------|
| llama-3.2-3b | 350-700 tok/s | 40-50 tok/s | ~3GB |
| hermes-4-14b | 220-7800 tok/s* | 20 tok/s | ~14GB |
| hermes-4-70b | 78-112 tok/s | 3.4 tok/s | ~52GB |

*Cached prompts process much faster

## Memory Usage

Approximate memory usage for the default configuration:

| Model | Model Size | KV Cache | Total |
|-------|------------|----------|-------|
| llama-3.2-3b (32K ctx) | ~2GB | ~1GB | ~3GB |
| hermes-4-14b (32K ctx) | ~10GB | ~4GB | ~14GB |
| hermes-4-70b (64K ctx) | ~42GB | ~10GB | ~52GB |
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

### Creating Custom Transformers

Transformers modify requests/responses for specific providers. See `claude-code-router/hermes-direct.js` for an example.

Transformer interface:
```javascript
class MyTransformer {
  name = 'my-transformer';

  async transformRequestIn(request, provider) {
    // Modify request.body
    return { body: request.body, config: {} };
  }

  async transformResponseOut(response, provider) {
    // Modify response
    return response;
  }
}
module.exports = MyTransformer;
```

## Logs

Server logs are stored in `~/.llm-servers/`:

```bash
tail -f ~/.llm-servers/hermes-4-70b.log    # Watch model logs
tail -f ~/.llm-servers/hermes-4-14b.log
tail -f ~/.llm-servers/llama-3.2-3b.log
tail -f /tmp/ccr.log                        # Watch router logs
```

## System Status

Use the system status script to monitor everything:

```bash
./system-status.sh         # Snapshot
./system-status.sh -w      # Watch mode
```

Check model status:
```bash
./start-llm-server.sh status
```
