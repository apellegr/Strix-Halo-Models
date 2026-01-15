// Simple STREAM-like memory bandwidth benchmark
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <omp.h>

#define ARRAY_SIZE (256 * 1024 * 1024)  // 256M elements = 2GB per array
#define NTIMES 10

double mysecond() {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + (double)ts.tv_nsec * 1.0e-9;
}

int main() {
    double *a, *b, *c;
    double scalar = 3.0;
    double times[4][NTIMES];
    double avgtime[4] = {0}, maxtime[4] = {0}, mintime[4] = {1e10, 1e10, 1e10, 1e10};

    size_t bytes = ARRAY_SIZE * sizeof(double);

    printf("STREAM Memory Bandwidth Benchmark\n");
    printf("Array size: %zu MB (%.2f GB total)\n", bytes/1024/1024, 3.0*bytes/1024/1024/1024);
    printf("Threads: %d\n\n", omp_get_max_threads());

    // Allocate with NUMA-aware allocation
    a = (double*)aligned_alloc(64, bytes);
    b = (double*)aligned_alloc(64, bytes);
    c = (double*)aligned_alloc(64, bytes);

    if (!a || !b || !c) {
        printf("Failed to allocate memory\n");
        return 1;
    }

    // Initialize arrays (first touch for NUMA)
    #pragma omp parallel for
    for (size_t j = 0; j < ARRAY_SIZE; j++) {
        a[j] = 1.0;
        b[j] = 2.0;
        c[j] = 0.0;
    }

    printf("Running %d iterations...\n\n", NTIMES);

    for (int k = 0; k < NTIMES; k++) {
        double t;

        // COPY: c = a
        t = mysecond();
        #pragma omp parallel for
        for (size_t j = 0; j < ARRAY_SIZE; j++)
            c[j] = a[j];
        times[0][k] = mysecond() - t;

        // SCALE: b = scalar * c
        t = mysecond();
        #pragma omp parallel for
        for (size_t j = 0; j < ARRAY_SIZE; j++)
            b[j] = scalar * c[j];
        times[1][k] = mysecond() - t;

        // ADD: c = a + b
        t = mysecond();
        #pragma omp parallel for
        for (size_t j = 0; j < ARRAY_SIZE; j++)
            c[j] = a[j] + b[j];
        times[2][k] = mysecond() - t;

        // TRIAD: a = b + scalar * c
        t = mysecond();
        #pragma omp parallel for
        for (size_t j = 0; j < ARRAY_SIZE; j++)
            a[j] = b[j] + scalar * c[j];
        times[3][k] = mysecond() - t;
    }

    // Calculate statistics
    for (int k = 1; k < NTIMES; k++) {  // Skip first iteration
        for (int j = 0; j < 4; j++) {
            avgtime[j] += times[j][k];
            if (times[j][k] < mintime[j]) mintime[j] = times[j][k];
            if (times[j][k] > maxtime[j]) maxtime[j] = times[j][k];
        }
    }

    const char *label[4] = {"Copy", "Scale", "Add", "Triad"};
    double bw_factor[4] = {2, 2, 3, 3};  // bytes per element accessed

    printf("Function    Best Rate (GB/s)   Avg time   Min time   Max time\n");
    printf("---------------------------------------------------------------\n");
    for (int j = 0; j < 4; j++) {
        avgtime[j] /= (NTIMES - 1);
        double bw = (bw_factor[j] * bytes) / mintime[j] / 1e9;
        printf("%-8s    %12.2f       %8.4f   %8.4f   %8.4f\n",
               label[j], bw, avgtime[j], mintime[j], maxtime[j]);
    }

    free(a); free(b); free(c);
    return 0;
}
