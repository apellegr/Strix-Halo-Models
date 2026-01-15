# Session Context - January 8, 2026

## Problem Summary
LLM servers (llama-server) keep getting stuck/unresponsive after ~1 hour of operation.

## Root Cause Identified
AMD GPU driver (amdgpu) VPE (Video Processing Engine) ring test failures causing MODE2 GPU resets:
```
*ERROR* IB test failed on vpe (-110)
ib ring test failed (-110)
MODE2 reset
```

## System Info
- Kernel: 6.18.1-061801-generic
- ROCm: 7.1.1
- GPU: AMD Strix Halo (integrated)
- Router: Claude Code Router on port 3456

## Fix Applied
Disabled VPE IP block via kernel module parameter:
- Created /etc/modprobe.d/amdgpu-novpe.conf
- Set ip_block_mask=0xFFFFFDFF (disables bit 9 = VPE)

## LLM Server Setup
- llama-3.2-3b on port 8081 (fast/background tasks)
- hermes-4-14b on port 8082 (default/coder)
- hermes-4-70b on port 8083 (reasoning/think)

## Commands to Restart After Reboot
```bash
# Start LLM servers
cd /home/apellegr/Strix-Halo-Models
./start-llm-server.sh llama-3.2-3b 8081
./start-llm-server.sh hermes-4-14b 8082
./start-llm-server.sh hermes-4-70b 8083

# Check status
./start-llm-server.sh status

# Verify router is running
curl -s http://localhost:3456/health
```

## To Verify Fix Worked
After reboot, monitor for VPE errors:
```bash
sudo dmesg | grep -i "vpe\|error\|reset"
```

If no VPE errors appear and servers stay stable for >1 hour, the fix worked.

## Rollback (if needed)
```bash
sudo rm /etc/modprobe.d/amdgpu-novpe.conf
sudo update-initramfs -u
sudo reboot
```
