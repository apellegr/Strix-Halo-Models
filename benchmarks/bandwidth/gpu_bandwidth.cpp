// HIP GPU Memory Bandwidth Benchmark for Strix Halo APU
#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>

#define CHECK_HIP(call) do { \
    hipError_t err = call; \
    if (err != hipSuccess) { \
        printf("HIP error: %s at %s:%d\n", hipGetErrorString(err), __FILE__, __LINE__); \
        exit(1); \
    } \
} while(0)

// Simple copy kernel
__global__ void copy_kernel(double* dst, const double* src, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        dst[idx] = src[idx];
    }
}

// Scale kernel
__global__ void scale_kernel(double* dst, const double* src, double scalar, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        dst[idx] = scalar * src[idx];
    }
}

// Add kernel
__global__ void add_kernel(double* dst, const double* a, const double* b, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        dst[idx] = a[idx] + b[idx];
    }
}

// Triad kernel
__global__ void triad_kernel(double* dst, const double* a, const double* b, double scalar, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    if (idx < n) {
        dst[idx] = a[idx] + scalar * b[idx];
    }
}

int main() {
    // Test multiple sizes
    size_t sizes[] = {
        64 * 1024 * 1024,      // 512 MB per array
        128 * 1024 * 1024,     // 1 GB per array
        256 * 1024 * 1024,     // 2 GB per array
        512 * 1024 * 1024,     // 4 GB per array
    };
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);

    double *d_a, *d_b, *d_c;
    hipEvent_t start, stop;
    float elapsed_ms;
    int ntimes = 10;
    double scalar = 3.0;

    printf("GPU Memory Bandwidth Benchmark (HIP)\n");
    printf("=====================================\n\n");

    // Get device info
    hipDeviceProp_t prop;
    CHECK_HIP(hipGetDeviceProperties(&prop, 0));
    printf("Device: %s\n", prop.name);
    printf("Memory Clock: %d MHz\n", prop.memoryClockRate / 1000);
    printf("Memory Bus Width: %d bits\n", prop.memoryBusWidth);

    size_t free_mem, total_mem;
    CHECK_HIP(hipMemGetInfo(&free_mem, &total_mem));
    printf("Total Memory: %.2f GB\n", total_mem / 1e9);
    printf("Free Memory: %.2f GB\n\n", free_mem / 1e9);

    CHECK_HIP(hipEventCreate(&start));
    CHECK_HIP(hipEventCreate(&stop));

    for (int s = 0; s < num_sizes; s++) {
        size_t n = sizes[s];
        size_t bytes = n * sizeof(double);

        // Check if we have enough memory for 3 arrays
        if (3 * bytes > free_mem * 0.9) {
            printf("Skipping %.0f MB - not enough memory\n", bytes / 1e6);
            continue;
        }

        printf("Array Size: %.0f MB (%.2f GB total for 3 arrays)\n",
               bytes / 1e6, 3.0 * bytes / 1e9);

        CHECK_HIP(hipMalloc(&d_a, bytes));
        CHECK_HIP(hipMalloc(&d_b, bytes));
        CHECK_HIP(hipMalloc(&d_c, bytes));

        // Initialize
        CHECK_HIP(hipMemset(d_a, 0, bytes));
        CHECK_HIP(hipMemset(d_b, 0, bytes));
        CHECK_HIP(hipMemset(d_c, 0, bytes));

        int blockSize = 256;
        int numBlocks = (n + blockSize - 1) / blockSize;

        // Warmup
        copy_kernel<<<numBlocks, blockSize>>>(d_c, d_a, n);
        CHECK_HIP(hipDeviceSynchronize());

        double copy_bw = 0, scale_bw = 0, add_bw = 0, triad_bw = 0;

        for (int k = 0; k < ntimes; k++) {
            // Copy
            CHECK_HIP(hipEventRecord(start));
            copy_kernel<<<numBlocks, blockSize>>>(d_c, d_a, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            double bw = 2.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > copy_bw) copy_bw = bw;

            // Scale
            CHECK_HIP(hipEventRecord(start));
            scale_kernel<<<numBlocks, blockSize>>>(d_b, d_c, scalar, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            bw = 2.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > scale_bw) scale_bw = bw;

            // Add
            CHECK_HIP(hipEventRecord(start));
            add_kernel<<<numBlocks, blockSize>>>(d_c, d_a, d_b, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            bw = 3.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > add_bw) add_bw = bw;

            // Triad
            CHECK_HIP(hipEventRecord(start));
            triad_kernel<<<numBlocks, blockSize>>>(d_a, d_b, d_c, scalar, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            bw = 3.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > triad_bw) triad_bw = bw;
        }

        printf("  Copy:  %8.2f GB/s\n", copy_bw);
        printf("  Scale: %8.2f GB/s\n", scale_bw);
        printf("  Add:   %8.2f GB/s\n", add_bw);
        printf("  Triad: %8.2f GB/s\n\n", triad_bw);

        CHECK_HIP(hipFree(d_a));
        CHECK_HIP(hipFree(d_b));
        CHECK_HIP(hipFree(d_c));
    }

    CHECK_HIP(hipEventDestroy(start));
    CHECK_HIP(hipEventDestroy(stop));

    return 0;
}
