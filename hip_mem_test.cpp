#include <hip/hip_runtime.h>
#include <stdio.h>

int main() {
    size_t free_mem, total_mem;
    (void)hipMemGetInfo(&free_mem, &total_mem);
    printf("HIP Total GPU memory: %.2f GB\n", total_mem / 1024.0 / 1024.0 / 1024.0);
    printf("HIP Free GPU memory:  %.2f GB\n", free_mem / 1024.0 / 1024.0 / 1024.0);

    hipDeviceProp_t props;
    (void)hipGetDeviceProperties(&props, 0);
    printf("Device Name: %s\n", props.name);
    printf("Total Global Mem: %.2f GB\n", props.totalGlobalMem / 1024.0 / 1024.0 / 1024.0);
    return 0;
}
