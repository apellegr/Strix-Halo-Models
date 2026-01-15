// HIP Transfer Bandwidth Test (Host <-> Device)
#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CHECK_HIP(call) do { \
    hipError_t err = call; \
    if (err != hipSuccess) { \
        printf("HIP error: %s at %s:%d\n", hipGetErrorString(err), __FILE__, __LINE__); \
        exit(1); \
    } \
} while(0)

int main() {
    printf("HIP Transfer Bandwidth Test\n");
    printf("============================\n\n");

    hipEvent_t start, stop;
    CHECK_HIP(hipEventCreate(&start));
    CHECK_HIP(hipEventCreate(&stop));

    size_t sizes[] = {
        1ULL * 1024 * 1024 * 1024,    // 1 GB
        2ULL * 1024 * 1024 * 1024,    // 2 GB
        4ULL * 1024 * 1024 * 1024,    // 4 GB
        8ULL * 1024 * 1024 * 1024,    // 8 GB
        16ULL * 1024 * 1024 * 1024,   // 16 GB
    };
    int num_sizes = sizeof(sizes) / sizeof(sizes[0]);

    for (int s = 0; s < num_sizes; s++) {
        size_t bytes = sizes[s];
        float elapsed_ms;
        int ntimes = 3;

        printf("Transfer Size: %.0f GB\n", bytes / 1e9);

        // Allocate host and device memory
        void *h_data, *d_data;
        CHECK_HIP(hipHostMalloc(&h_data, bytes, hipHostMallocDefault));
        CHECK_HIP(hipMalloc(&d_data, bytes));

        // Initialize host data
        memset(h_data, 0x5A, bytes);

        // Warmup
        CHECK_HIP(hipMemcpy(d_data, h_data, bytes, hipMemcpyHostToDevice));
        CHECK_HIP(hipDeviceSynchronize());

        // H2D bandwidth
        double best_h2d = 0;
        for (int k = 0; k < ntimes; k++) {
            CHECK_HIP(hipEventRecord(start));
            CHECK_HIP(hipMemcpy(d_data, h_data, bytes, hipMemcpyHostToDevice));
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            double bw = bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > best_h2d) best_h2d = bw;
        }

        // D2H bandwidth
        double best_d2h = 0;
        for (int k = 0; k < ntimes; k++) {
            CHECK_HIP(hipEventRecord(start));
            CHECK_HIP(hipMemcpy(h_data, d_data, bytes, hipMemcpyDeviceToHost));
            CHECK_HIP(hipEventRecord(stop));
            CHECK_HIP(hipEventSynchronize(stop));
            CHECK_HIP(hipEventElapsedTime(&elapsed_ms, start, stop));
            double bw = bytes / (elapsed_ms / 1000.0) / 1e9;
            if (bw > best_d2h) best_d2h = bw;
        }

        printf("  Host->Device: %8.2f GB/s\n", best_h2d);
        printf("  Device->Host: %8.2f GB/s\n\n", best_d2h);

        CHECK_HIP(hipFree(d_data));
        CHECK_HIP(hipHostFree(h_data));
    }

    CHECK_HIP(hipEventDestroy(start));
    CHECK_HIP(hipEventDestroy(stop));

    return 0;
}
