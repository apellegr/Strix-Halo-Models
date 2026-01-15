# Makefile for memory bandwidth benchmarks
# For AMD Strix Halo APU

CC = gcc
HIPCC = hipcc
CFLAGS = -O3 -march=native -fopenmp
HIPFLAGS = -O3 --offload-arch=gfx1151

# ROCm environment
export HSA_OVERRIDE_GFX_VERSION ?= 11.5.1

.PHONY: all clean cpu gpu gpu_large transfer

all: mem_bandwidth gpu_bandwidth gpu_bandwidth_large transfer_bandwidth hip_alloc_test

# CPU STREAM benchmark
cpu: mem_bandwidth
mem_bandwidth: mem_bandwidth.c
	$(CC) $(CFLAGS) -o $@ $< -lm

# GPU device memory bandwidth
gpu: gpu_bandwidth
gpu_bandwidth: gpu_bandwidth.cpp
	$(HIPCC) $(HIPFLAGS) -o $@ $<

# GPU large allocation bandwidth
gpu_large: gpu_bandwidth_large
gpu_bandwidth_large: gpu_bandwidth_large.cpp
	$(HIPCC) $(HIPFLAGS) -o $@ $<

# Host-Device transfer bandwidth
transfer: transfer_bandwidth
transfer_bandwidth: transfer_bandwidth.cpp
	$(HIPCC) $(HIPFLAGS) -o $@ $<

# HIP memory allocation test
alloc: hip_alloc_test
hip_alloc_test: hip_alloc_test.cpp
	$(HIPCC) $(HIPFLAGS) -o $@ $<

clean:
	rm -f mem_bandwidth gpu_bandwidth gpu_bandwidth_large transfer_bandwidth hip_alloc_test

# Run all benchmarks
run: all
	@echo "=== CPU Memory Bandwidth ==="
	OMP_NUM_THREADS=16 ./mem_bandwidth
	@echo ""
	@echo "=== GPU Device Memory Bandwidth ==="
	HSA_ENABLE_SDMA=0 ./gpu_bandwidth
	@echo ""
	@echo "=== GPU Large Allocation Bandwidth ==="
	HSA_ENABLE_SDMA=0 ./gpu_bandwidth_large
	@echo ""
	@echo "=== Host-Device Transfer Bandwidth ==="
	HSA_ENABLE_SDMA=0 ./transfer_bandwidth
