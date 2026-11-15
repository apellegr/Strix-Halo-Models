# Model evals for localai

Quick quality checks used to compare models and llama.cpp builds on the Strix Halo box. All three
scripts use only the Python standard library at runtime, except `make_vision_set.py`, which needs Pillow.

| Script | What it checks |
|---|---|
| `fa_eval.py` | Family-assistant tool use: real system prompt + 17 tool specs loaded from `agent.py`, 10 scenarios, tools mocked |
| `make_vision_set.py` | Builds 6 synthetic images with known answers (receipt OCR, counting, bar chart, sign, schedule table, colours) |
| `vision_eval.py` | Scores a vision model on that image set |
| `make_video_set.py` | Builds 4 synthetic clips needing temporal understanding (motion direction, digit order, porch delivery, traffic light); needs ffmpeg |
| `video_eval.py` | Scores a model on those clips; the server needs `--mmproj` and ffmpeg (`--video-ffmpeg-dir`) |

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

Final comparison (2026-11-13, b12259 + ROCm 10.0, fa_eval 2 runs with the false-claim check):

| Model | fa_eval | vision | video | fa median | GPU mem |
|---|---|---|---|---|---|
| **Qwen3.8-27B + mmproj** (chosen) | 20/20, 0 false claims | 6/6 (~8 s) | 4/4 (~15 s/clip) | 10.6 s | ~23 GiB |
| Qwen3.6-35B-A3B, thinking on | 20/20, 0 | 6/6 (~5 s) | not tested | 6.6 s | 22 GiB |
| Qwen3.6-35B-A3B, thinking off | 19/20, 0 | 6/6 (~1.3 s) | not tested | 2.2 s | 22 GiB |
| Gemma 4 26B-A4B | 20/20, 0 | 6/6 (~6.6 s) | not tested | 10.7 s | 18 GiB |
| GLM-4.7-Flash (retired) | 17/20, **2 false claims** | n/a | n/a | 9.0 s | ~19 GiB |
| Qwen3-VL-30B-A3B (retired) | n/a | 5/6 (~1.7 s) | not tested | n/a | ~20 GiB |

Qwen3.8 now serves Home Assistant vision, family-assistant and video alone, with `--parallel 2`.
Under concurrent image + family-assistant load both stayed correct; latency rose to ~12 s / ~14 s.
