# Model evals for localai

Quick quality checks used to compare models and llama.cpp builds on the Strix Halo box. All three
scripts use only the Python standard library at runtime, except `make_vision_set.py`, which needs Pillow.

| Script | What it checks |
|---|---|
| `fa_eval.py` | Family-assistant tool use: real system prompt + 17 tool specs loaded from `agent.py`, 10 scenarios, tools mocked |
| `make_vision_set.py` | Builds 6 synthetic images with known answers (receipt OCR, counting, bar chart, sign, schedule table, colours) |
| `vision_eval.py` | Scores a vision model on that image set |

```bash
# family-assistant tool use (2 runs per scenario)
python3 -I fa_eval.py ~/workspace/Treehouse/services/family-assistant http://localhost:8002/v1 GLM 2

# vision (localai has no Pillow, so build the set elsewhere and copy it over)
python3 make_vision_set.py /tmp/vset
python3 -I vision_eval.py /tmp/vset 8010 QwenVL
```

`fa_eval.py` never touches Gmail, Calendar or the assistant's memory: it loads `agent.py` with a throwaway
`DATA_DIR` and dummy Google credentials only so the Google tools and playbook appear in the prompt, and it
answers every tool call from a fixed mock. Each scenario is also checked for a **false claim**: the model
says it added, sent or logged something without calling a state-changing tool.

## Why these exist (2026-11-12)

- **Short-prompt benchmarks miss long-prompt breakage.** llama.cpp b10361 running on the wrong ROCm
  runtime handled short prompts fine but produced garbage with family-assistant's ~3.7k-token system
  prompt (GLM scored 2/10, burning its whole token budget). `fa_eval.py` caught it.
- **Run one side model at a time.** The three production models use ~69 GiB of GPU memory; adding a fourth
  exhausted RAM and swapped, which also slowed production. Pause a service first.

Results from that day (b12259 + ROCm 10.0):

| Model | fa_eval | vision | median latency |
|---|---|---|---|
| GLM-4.7-Flash | 36/40, 0 false claims | n/a | ~6 s |
| Qwen3.8-27B | 10/10 | n/a | ~12 s |
| Qwen3-VL-30B-A3B | 6/10 | 5/6 | ~2 s |
| Qwen3.6-35B-A3B (thinking off) | 18/20, 1 false claim | 6/6 | ~2.4 s (measured under memory pressure) |
