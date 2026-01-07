# Claude Code Router Setup

This folder contains the configuration and installation scripts for running Claude Code with local LLM models on Strix Halo.

## Overview

The Claude Code Router (`@musistudio/claude-code-router`) acts as a proxy that intercepts Claude API requests and routes them to local LLM servers based on the task type.

### Model Configuration

| Role | Model | Port | Context | Speed | Purpose |
|------|-------|------|---------|-------|---------|
| **background** | llama-3.2-3b | 8081 | 8K | 68.8 tok/s | Fast tasks: titles, topics |
| **default** | qwen2.5-coder-32b | 8082 | 32K | 10.5 tok/s | Main coding work |
| **think** | deepseek-r1-32b | 8083 | 32K | 10.5 tok/s | Complex reasoning |

### Optimizations Applied

- **GPU Layers**: Benchmarked for optimal performance on Strix Halo
- **Batch Size**: 1024 (increased from default 512)
- **Flash Attention**: Enabled for faster attention computation
- **Parallel Slots**: 1 (dedicated processing per request)
- **Context Sizes**: Tuned for Claude Code's ~18K system prompt

## Installation

### 1. Install the Router

```bash
cd claude-code-router
./install.sh
```

This will:
- Install `@musistudio/claude-code-router` globally via npm
- Copy the configuration to `~/.claude-code-router/config.json`
- Create a systemd user service (optional)

### 2. Start the Models

```bash
cd ..
./start-claude-code-models.sh
```

Or start models and router together:
```bash
./start-claude-code-models.sh all
```

### 3. Configure Claude Code

Set the API base URL to use the router:

```bash
export ANTHROPIC_BASE_URL=http://localhost:3456
claude
```

Or add to your shell profile:
```bash
echo 'export ANTHROPIC_BASE_URL=http://localhost:3456' >> ~/.bashrc
```

## Files

| File | Description |
|------|-------------|
| `config.json` | Router configuration with model mappings |
| `install.sh` | Installation script for the router |
| `../start-claude-code-models.sh` | Start all models for Claude Code |
| `../model-configs.json` | Optimized model configurations |

## Configuration Details

### Router Config (`config.json`)

```json
{
  "Router": {
    "background": "local-fast,llama-3.2-3b",
    "default": "local-coder,qwen2.5-coder-32b",
    "think": "local-reasoning,deepseek-r1-32b",
    "longContext": "local-coder,qwen2.5-coder-32b",
    "webSearch": "local-fast,llama-3.2-3b",
    "image": "local-coder,qwen2.5-coder-32b"
  }
}
```

### Model Routing

| Claude Code Task | Routed To | Reason |
|------------------|-----------|--------|
| Title generation | llama-3.2-3b | Fast, simple task |
| Topic detection | llama-3.2-3b | Fast, simple task |
| Main conversation | qwen2.5-coder-32b | Good coding ability |
| Complex reasoning | deepseek-r1-32b | DeepSeek R1 reasoning |
| Long context | qwen2.5-coder-32b | 32K context |

## Management Commands

```bash
# Start all models
./start-claude-code-models.sh

# Stop all models
./start-claude-code-models.sh stop

# Check status
./start-claude-code-models.sh status

# Start router only
./start-claude-code-models.sh router

# Start everything
./start-claude-code-models.sh all
```

## Systemd Service (Optional)

To run the router as a service:

```bash
# Enable auto-start
systemctl --user enable claude-code-router

# Start service
systemctl --user start claude-code-router

# Check status
systemctl --user status claude-code-router

# View logs
journalctl --user -u claude-code-router -f
```

## Troubleshooting

### Context Size Errors

If you see errors like "request exceeds available context size", the model's context is too small. Check:

```bash
./start-llm-server.sh status
```

The default/reasoning models need at least 32K context for Claude Code.

### Memory Issues

With all three models loaded, expect ~60GB memory usage. Check with:

```bash
free -h
```

If memory is tight, you can use smaller models or reduce context sizes.

### Router Not Responding

Check if the router is running:

```bash
curl http://localhost:3456/health
```

View router logs:

```bash
tail -f ~/.claude-code-router/logs/*.log
```

### Model Not Responding

Check individual model health:

```bash
curl http://localhost:8081/health  # llama-3.2-3b
curl http://localhost:8082/health  # qwen2.5-coder-32b
curl http://localhost:8083/health  # deepseek-r1-32b
```

View model logs:

```bash
tail -f ~/.llm-servers/<model-name>.log
```

## Benchmark Results

Results from `./benchmark-model.sh <model> --optimize`:

| Model | GPU Layers | Prompt (tok/s) | Generation (tok/s) | Memory |
|-------|------------|----------------|-------------------|--------|
| llama-3.2-3b | 50 | 2,154 | 68.8 | ~8GB |
| qwen2.5-coder-32b | 80 | 317 | 10.5 | ~24GB |
| deepseek-r1-32b | 80 | 316 | 10.5 | ~24GB |

## Alternative Configurations

### Lighter Setup (Less Memory)

Use smaller models for all tasks:

```bash
# Edit config.json to use:
# - qwen2.5-7b for background
# - deepseek-coder-v2-16b for default
# - Skip reasoning model
```

### Heavier Setup (Better Quality)

Use larger models for better responses:

```bash
# Edit config.json to use:
# - qwen2.5-7b for background
# - qwen3-235b for default/think
```

Note: qwen3-235b requires ~100GB memory and is much slower.
