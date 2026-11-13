#include <mpi.h>
#include <cuda_runtime_api.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void cuda_check(cudaError_t status) {
    if (status != cudaSuccess) {
        fprintf(stderr, "CUDA diagnostic failed: %s\n", cudaGetErrorString(status));
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
}

int main(int argc, char **argv) {
    MPI_Init(&argc, &argv);
    int rank, size, host_length;
    char host[MPI_MAX_PROCESSOR_NAME] = {0};
    MPI_Comm_rank(MPI_COMM_WORLD, &rank);
    MPI_Comm_size(MPI_COMM_WORLD, &size);
    MPI_Get_processor_name(host, &host_length);
    if (size < 2) {
        fprintf(stderr, "MPI smoke test requires at least two ranks.\n");
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    char *hosts = calloc((size_t) size, MPI_MAX_PROCESSOR_NAME);
    if (!hosts) MPI_Abort(MPI_COMM_WORLD, 1);
    MPI_Allgather(host, MPI_MAX_PROCESSOR_NAME, MPI_CHAR,
                  hosts, MPI_MAX_PROCESSOR_NAME, MPI_CHAR, MPI_COMM_WORLD);
    int distinct = 0;
    for (int i = 0; i < size; ++i) {
        int first = 1;
        for (int j = 0; j < i; ++j)
            if (strcmp(hosts + i * MPI_MAX_PROCESSOR_NAME,
                       hosts + j * MPI_MAX_PROCESSOR_NAME) == 0) first = 0;
        distinct += first;
    }
    free(hosts);
    const char *minimum = getenv("MPI_SMOKE_MIN_NODES");
    if (minimum && distinct < atoi(minimum)) {
        fprintf(stderr, "MPI ranks did not span the required node count.\n");
        MPI_Abort(MPI_COMM_WORLD, 1);
    }
    int value = rank + 1, received = 0, reduced = 0;
    int previous = (rank + size - 1) % size, next = (rank + 1) % size;
    MPI_Allreduce(&value, &reduced, 1, MPI_INT, MPI_SUM, MPI_COMM_WORLD);
    if (reduced != size * (size + 1) / 2) MPI_Abort(MPI_COMM_WORLD, 1);
    int gpu = argc > 1 && strcmp(argv[1], "--gpu") == 0;
    if (gpu) {
        int devices, runtime_version, driver_version;
        cuda_check(cudaGetDeviceCount(&devices));
        if (devices < 1) MPI_Abort(MPI_COMM_WORLD, 1);
        cuda_check(cudaSetDevice(0)); /* Slurm supplies CUDA_VISIBLE_DEVICES. */
        cuda_check(cudaRuntimeGetVersion(&runtime_version));
        cuda_check(cudaDriverGetVersion(&driver_version));
        if (driver_version < runtime_version) MPI_Abort(MPI_COMM_WORLD, 1);
        int *send_device, *receive_device;
        cuda_check(cudaMalloc((void **) &send_device, sizeof(int)));
        cuda_check(cudaMalloc((void **) &receive_device, sizeof(int)));
        cuda_check(cudaMemcpy(send_device, &value, sizeof(int), cudaMemcpyHostToDevice));
        MPI_Sendrecv(send_device, 1, MPI_INT, next, 7, receive_device, 1, MPI_INT,
                     previous, 7, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
        cuda_check(cudaMemcpy(&received, receive_device, sizeof(int), cudaMemcpyDeviceToHost));
        cuda_check(cudaFree(send_device));
        cuda_check(cudaFree(receive_device));
    } else {
        MPI_Sendrecv(&value, 1, MPI_INT, next, 7, &received, 1, MPI_INT,
                     previous, 7, MPI_COMM_WORLD, MPI_STATUS_IGNORE);
    }
    if (received != previous + 1) MPI_Abort(MPI_COMM_WORLD, 1);
    printf("rank=%d host=%s nodes=%d cuda_buffers=%d verified=1\n", rank, host, distinct, gpu);
    MPI_Finalize();
    return 0;
}
