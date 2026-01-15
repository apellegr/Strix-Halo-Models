# TODO

## Performance Optimization

- [ ] **Investigate hermes-4-70b GPU layers**: Currently using 50 GPU layers (~30 layers on CPU). Consider increasing to 60-80 layers when not running all three models simultaneously for faster generation. Current config uses ~52GB VRAM; increasing to 80 layers would use ~70GB but significantly reduce CPU bottleneck.

- [ ] **Rebalance router task allocation**: hermes-4-14b is underutilized (981 output tokens) while hermes-4-70b handles most requests (6.6K output tokens). Consider routing more task types to 14B for 7x faster generation (11 tok/s vs 1.5 tok/s). Trade-off: speed vs reasoning quality.

## Future Improvements

- [ ] Add streaming response support to hermes-tool-adapter transformer
- [ ] Consider adding Prometheus metrics endpoint for monitoring
- [ ] Test with other model combinations (Qwen, DeepSeek, etc.)
