#include <hip/hip_runtime.h>
#include <stdio.h>
#include <stdlib.h>

int main(int argc, char** argv) {
    size_t target_gb = 70; // Default: try 70GB
    if (argc > 1) {
        target_gb = atoi(argv[1]);
    }

    size_t free_mem, total_mem;
    hipMemGetInfo(&free_mem, &total_mem);
    printf("Before allocation:\n");
    printf("  HIP Total: %.2f GB\n", total_mem / 1024.0 / 1024.0 / 1024.0);
    printf("  HIP Free:  %.2f GB\n", free_mem / 1024.0 / 1024.0 / 1024.0);

    size_t alloc_size = target_gb * 1024ULL * 1024ULL * 1024ULL;
    printf("\nAttempting to allocate %.2f GB...\n", alloc_size / 1024.0 / 1024.0 / 1024.0);

    void* ptr = nullptr;
    hipError_t err = hipMalloc(&ptr, alloc_size);

    if (err != hipSuccess) {
        printf("hipMalloc FAILED: %s\n", hipGetErrorString(err));

        // Binary search for max allocation
        printf("\nFinding maximum allocation size...\n");
        size_t low = 1ULL * 1024 * 1024 * 1024;  // 1 GB
        size_t high = alloc_size;
        size_t max_success = 0;

        while (low <= high) {
            size_t mid = (low + high) / 2;
            err = hipMalloc(&ptr, mid);
            if (err == hipSuccess) {
                max_success = mid;
                hipFree(ptr);
                low = mid + (1024ULL * 1024 * 1024); // Step by 1GB
            } else {
                high = mid - (1024ULL * 1024 * 1024);
            }
        }

        printf("Maximum single allocation: %.2f GB\n", max_success / 1024.0 / 1024.0 / 1024.0);
    } else {
        printf("hipMalloc SUCCESS!\n");

        hipMemGetInfo(&free_mem, &total_mem);
        printf("\nAfter allocation:\n");
        printf("  HIP Free:  %.2f GB\n", free_mem / 1024.0 / 1024.0 / 1024.0);

        hipFree(ptr);
        printf("Memory freed.\n");
    }

    return 0;
}
