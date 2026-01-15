// HIP GPU Memory Bandwidth - Large allocation test
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

__global__ void copy_kernel(double* dst, const double* src, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    size_t stride = blockDim.x * gridDim.x;
    for (size_t i = idx; i < n; i += stride) {
        dst[i] = src[i];
    }
}

__global__ void triad_kernel(double* dst, const double* a, const double* b, double scalar, size_t n) {
    size_t idx = blockIdx.x * blockDim.x + threadIdx.x;
    size_t stride = blockDim.x * gridDim.x;
    for (size_t i = idx; i < n; i += stride) {
        dst[i] = a[i] + scalar * b[i];
    }
}

int main() {
    double *d_a, *d_b, *d_c;
    hipEvent_t start, stop;
    float elapsed_ms;
    int ntimes = 5;
    double scalar = 3.0;

    printf("GPU Memory Bandwidth - Large Allocation Test\n");
    printf("=============================================\n\n");

    size_t free_mem, total_mem;
    CHECK_HIP(hipMemGetInfo(&free_mem, &total_mem));
    printf("Free Memory: %.2f GB\n\n", free_mem / 1e9);

    CHECK_HIP(hipEventCreate(&start));
    CHECK_HIP(hipEventCreate(&stop));

    // Test with very large allocations - 20GB, 40GB, 60GB per array
    size_t sizes_gb[] = {10, 20, 30};
    int num_sizes = sizeof(sizes_gb) / sizeof(sizes_gb[0]);

    for (int s = 0; s < num_sizes; s++) {
        size_t bytes = sizes_gb[s] * 1024ULL * 1024ULL * 1024ULL;
        size_t n = bytes / sizeof(double);

        // Need 3 arrays
        if (3 * bytes > free_mem * 0.95) {
            printf("Skipping %zu GB - need %.1f GB for 3 arrays\n", sizes_gb[s], 3.0 * bytes / 1e9);
            continue;
        }

        printf("Array Size: %zu GB (%.1f GB total for 3 arrays)\n", sizes_gb[s], 3.0 * bytes / 1e9);

        CHECK_HIP(hipMalloc(&d_a, bytes));
        CHECK_HIP(hipMalloc(&d_b, bytes));
        CHECK_HIP(hipMalloc(&d_c, bytes));

        // Initialize to force page allocation
        CHECK_HIP(hipMemset(d_a, 1, bytes));
        CHECK_HIP(hipMemset(d_b, 2, bytes));
        CHECK_HIP(hipMemset(d_c, 0, bytes));
        CHECK_HIP(hipDeviceSynchronize());

        int blockSize = 256;
        int numBlocks = 1024;  // Fixed grid size for large arrays

        // Warmup
        copy_kernel<<<numBlocks, blockSize>>>(d_c, d_a, n);
        CHECK_HIP(hipDeviceSynchronize());

        double best_copy = 0, best_triad = 0;

        for (int k = 0; k < ntimes; k++) {
            // Copy
            CHECK_HIP(hipEventRecord(start));
            copy_kernel<<<numBlocks, blockSize>>>(d_c, d_a, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            double bw = 2.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > best_copy) best_copy = bw;

            // Triad
            CHECK_HIP(hipEventRecord(start));
            triad_kernel<<<numBlocks, blockSize>>>(d_a, d_b, d_c, scalar, n);
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            bw = 3.0 * bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > best_triad) best_triad = bw;
        }

        printf("  Copy:  %8.2f GB/s\n", best_copy);
        printf("  Triad: %8.2f GB/s\n\n", best_triad);

        CHECK_HIP(hipFree(d_a));
        CHECK_HIP(hipFree(d_b));
        CHECK_HIP(hipFree(d_c));
    }

    CHECK_HIP(hipEventDestroy(start));
    CHECK_HIP(hipEventDestroy(stop));

    return 0;
}
