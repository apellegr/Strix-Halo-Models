# Test Session Log - 2026-01-21

## Session Start: 18:40 UTC

## System Info
- CPU: AMD Ryzen AI MAX+ 395 w/ Radeon 8060S
- GPU: Integrated Radeon Graphics (gfx1151)
- RAM: 122GB
- Kernel: 6.18.6-061806-generic
- ROCm: 7.1.1

## Previous Crash Analysis
- **Time**: ~18:29-18:30 UTC
- **Cause**: System shutdown during benchmark 61/75
- **Last successful test**: ngl=80, batch=1024, tg8 (generation test)
- **Crash point**: Transitioning to ngl=81 while running `gpu-max-power.sh`
- **Evidence**: Logs end abruptly with no error messages (hard power-off)
- **Likely cause**: Thermal/power protection triggered by:
  1. Maximum GPU layer offload (81 layers)
  2. Aggressive power limits (140W STAPM/PPT)

## Current Test Plan
- Resume sweep with MORE CONSERVATIVE settings
- Monitor temperature and power continuously
- Log state before each test configuration

## Monitoring Setup
- [ ] Background gpu-monitor.sh running
- [ ] Thermal monitoring active
- [ ] Test state logged before each run

---

## Test Runs

### Test 1: GPU Layers Sweep (ngl 70-81)
- **Time**: 2026-01-21 18:45 UTC
- **Config**: qwen3-235b-thinking Q3_K_M
- **GPU Layers**: 70, 75, 78, 80, 81 (incremental)
- **Batch Size**: 512 (fixed)
- **Prompt Sizes**: 512 tokens
- **Pre-test Temp**: GPU 33°C, CPU 35°C
- **Pre-test Power**: ~10W idle
- **Monitor Log**: stress-results/gpu-monitor-20260121_184505.log
- **Status**: RUNNING

#### Test Progress:
- [X] ngl=70 - BLOCKED: HSA segfault on kernel 6.18.6
- [ ] ngl=75
- [ ] ngl=78
- [ ] ngl=80 - last known stable from previous session
- [ ] ngl=81 - crash point from previous session

### BLOCKER: Wrong Kernel!
**Current kernel**: 6.18.6-061806-generic
**Required kernel**: 6.14.0-37-generic

ROCm 7.1.1 has HSA runtime incompatibility with kernel 6.18.x - causes segfault at startup.
Need to reboot into kernel 6.14.0-37-generic to continue testing.

**Fix applied**: Run `sudo ./set-kernel-6.14.sh && sudo reboot`

## After Reboot Checklist
1. Verify kernel: `uname -r` should show `6.14.0-37-generic`
2. Test GPU: `rocm-smi --showtemp`
3. Quick benchmark test:
   ```bash
   source ~/.rocm-env.sh
   export LD_LIBRARY_PATH="$HOME/.local/lib:$LD_LIBRARY_PATH"
   ~/.local/bin/llama-bench -m ~/Strix-Halo-Models/models/fast/llama-3.2-3b/Llama-3.2-3B-Instruct-Q6_K_L.gguf -ngl 99 -p 64 -n 16
   ```
4. Resume sweep: Continue with ngl=70 test for qwen3-235b-thinking

---

## Monitoring Capabilities

### Available Sensors
| Sensor | Source | Current | Purpose |
|--------|--------|---------|---------|
| GPU Temp | amdgpu hwmon | 33°C | GPU die temperature |
| CPU/APU Temp | k10temp hwmon | 35°C | Package temperature |
| GPU Power | rocm-smi | ~10W | GPU power draw |
| Package Power | RAPL | Available | Total APU power |
| GPU Utilization | rocm-smi | 0% | GPU busy % |
| Memory | free | 122GB total | System RAM |

### Thermal Limits
- **Trip Point**: 110°C (from ACPI thermal zone)
- **Cooling devices**: 38 available (CPU frequency throttling)

### Known Issues
- **ryzenadj NOT WORKING** (Secure Boot / PCI Bus not writable)
- Cannot actively set power limits - system uses defaults
- GPU performance level: auto (cannot force without sudo)

### Monitoring Commands
```bash
# Start background monitor (run in separate terminal)
./gpu-monitor.sh --log-only &

# Quick status check
rocm-smi --showtemp --showpower --showuse

# CPU temp
cat /sys/class/hwmon/hwmon2/temp1_input | awk '{print $1/1000 "C"}'

# All temps at once
for d in /sys/class/hwmon/hwmon*/; do echo "$(cat $d/name 2>/dev/null): $(cat $d/temp1_input 2>/dev/null | awk '{print $1/1000}')C"; done
```

## Notes
- GPU idle temp: 33°C
- CPU/APU idle temp: 35°C
- GPU idle power: ~10W

---

## Session 2: 2026-01-21 (Post-Reboot)

### Kernel Verified
- `uname -r`: 6.14.0-37-generic ✓
- ROCm working: GPU 34°C at start

### GPU Layer Sweep Results (batch_size=512)

| ngl | pp512 (t/s) | tg32 (t/s) | Status |
|-----|-------------|------------|--------|
| 70  | 157.57 ± 1.56 | 11.29 ± 0.03 | ✓ |
| 75  | 158.55 ± 1.45 | 10.91 ± 0.56 | ✓ |
| 78  | 158.56 ± 1.26 | 11.17 ± 0.63 | ✓ |
| 80  | 159.08 ± 1.36 | **11.65 ± 0.15** | ✓ **Best tg** |
| 81  | 159.04 ± 1.16 | 11.40 ± 0.42 | ✓ |
| 82  | - | - | ✗ OOM |

### Analysis

**Previous Crash Root Cause**: The crash at ngl=81 in the previous session was NOT caused by the GPU layer count. With normal power settings (no `gpu-max-power.sh`), ngl=81 runs fine. The crash was likely caused by:
1. Aggressive power limits (140W STAPM/PPT) combined with max GPU offload
2. Thermal/power protection trigger

**Optimal Configuration**:
- **Best overall**: ngl=80 (best token generation at 11.65 t/s)
- **Max stable**: ngl=81 (slightly lower tg but more GPU offload)
- Prompt processing is essentially flat across 70-81 layers (~158-159 t/s)

**Thermal Performance**:
- Pre-test: 32°C
- Peak during tests: 41°C
- Post-test: 40°C
- Well within safe operating range

---

### Extended Stress Test (ngl=80, batch=512, 5 reps)

| Test | Tokens/sec | Variance |
|------|-----------|----------|
| pp256 | 96.94 | ± 11.67 (high - cold cache) |
| pp512 | 147.09 | ± 1.06 |
| pp1024 | 142.19 | ± 1.30 |
| pp2048 | 142.45 | ± 1.65 |
| tg64 | 11.54 | ± 0.03 |
| tg128 | 11.52 | ± 0.04 |

- Duration: ~5 minutes sustained load
- GPU temp: 36°C → 50°C (stable)

---

### Batch Size Optimization

| Test | batch=512 | batch=1024 | batch=2048 | batch=4096 |
|------|-----------|------------|------------|------------|
| pp512 | 147 | 159 | **162** | 160 |
| pp1024 | 142 | 156 | 154 | 155 |
| pp2048 | 142 | 144 | 143 | 143 |
| pp4096 | - | - | - | 126 |
| tg128 | 11.5 | 11.6 | 11.6 | 11.5 |

**Winner**: batch=2048 (best pp512 at 162 t/s)

---

## Final Optimized Configuration

```json
{
  "qwen3-235b-thinking": {
    "gpu_layers": 80,
    "ctx_size": 4096,
    "batch_size": 2048,
    "n_predict": 8192
  }
}
```

### Performance Summary
| Metric | Value |
|--------|-------|
| Prompt Processing (pp512) | 162 t/s |
| Prompt Processing (pp1024) | 154 t/s |
| Prompt Processing (pp2048) | 143 t/s |
| Token Generation | 11.6 t/s |
| Max GPU Layers | 81 (82+ OOM) |
| Optimal GPU Layers | 80 |

### Server Deployed
- **Port**: 8081
- **API**: http://localhost:8081/v1
- **Status**: Running ✓
- **Commit**: ad1d77c (pushed to origin/main)

---

## Session Complete: 2026-01-21 ~19:30 UTC

### Key Findings
1. **ngl=80 is optimal** - Best token generation (11.65 t/s), ngl=81 works but slightly slower
2. **batch=2048 is optimal** - 10% faster prompt processing vs batch=512
3. **n_predict=8192** - Added for thinking model's longer reasoning chains
4. **Previous crash root cause** - `gpu-max-power.sh` aggressive power limits, not GPU layers
5. **Thermals stable** - Never exceeded 50°C during extended testing

### Changes Committed
- Updated `model-configs.json` with optimized settings
- Updated `start-llm-server.sh` to support n_predict parameter
- Pushed to origin/main

---

## Previous Session (Pre-Reboot)

=== Test: ngl=70 ===
Start: 2026-01-21T18:45:54+00:00
