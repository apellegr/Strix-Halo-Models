# TODO

## Performance Optimization

- [x] **RESOLVED: ROCm memory limit** (2026-01-15): Fixed with TTM kernel params + `--no-mmap` flag. Now using 90GB GPU memory (was 61GB). See ROCM-MEMORY-LIMIT-INVESTIGATION.md.

- [x] **Optimized hermes-4-70b**: Now fully GPU offloaded (999 layers) with 90GB available. ~40GB model fully on GPU.

- [x] **Optimized qwen3-235b-thinking**: Increased from 55 to 81 GPU layers (85% offload). Uses ~90GB GPU memory.

- [ ] **Rebalance router task allocation**: hermes-4-14b is underutilized (981 output tokens) while hermes-4-70b handles most requests (6.6K output tokens). Consider routing more task types to 14B for 7x faster generation (11 tok/s vs 1.5 tok/s). Trade-off: speed vs reasoning quality.

## Future Improvements

- [ ] Add streaming response support to hermes-tool-adapter transformer
- [ ] Consider adding Prometheus metrics endpoint for monitoring
- [ ] Test with other model combinations (Qwen, DeepSeek, etc.)
