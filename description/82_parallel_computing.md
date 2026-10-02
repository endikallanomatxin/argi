# Parallel computing (future design proposal)

> [!IDEA]
> This document explores a possible model for parallel execution on GPUs
> and CPUs. The types, syntax, and code below are sketches, not accepted
> language or library APIs.

The main question is whether execution groups, memory domains, and supported
operations can be described as data that a compiler uses to select and
optimize parallel work. Such a model would need to account for memory
hierarchies and tiling without tying Argi to one device API.
For example, small matrix multiplication could use hardware operations and
tiling chosen for the device's register, shared-memory, and cache levels.

## Hardware description sketch

One possible description has processing groups, memory domains, and
operations. The following is pseudocode; field types and construction syntax
are deliberately incomplete.

```
ParallelProcessingUnit : Type = (
    .parallel_groups
    .memory_domains
    .operations
)

ParallelGroup : Type = (
    .name: String
    .groups: Nullable#(.t: &ParallelGroup)
    .number: UIntNative
)

ParallelMemory : Type = (
    .name: String
    .shared_across: Nullable#(.t: &ParallelGroup)
    .size: UIntNative
    .latency: UIntNative
    .access_mode: String
)

ParallelOperation : Type = (
    .name: String
    .supported_by: Nullable#(.t: &ParallelGroup)
    .supported_data_types
    .latency: UIntNative
    .throughput: UIntNative
    .invocation_name: String
    .native_implementation: String
)

thread : ParallelGroup = (
    .name = "Thread",
    .groups = ..none,   // There is no parent group.
    .number = 1         // Each thread is independent.
)


// Cuda Example

// Parallel Groups

block : ParallelGroup = (
    .name = "Block",
    .groups = ..some(.value = &thread),  // Blocks contain threads.
    .number = 16
)

grid : ParallelGroup = (
    .name = "Grid",
    .groups = ..some(.value = &block),   // Grid contains blocks.
    .number = 4
)

// Memory Domains

registers : ParallelMemory = (
    .name = "Registers",
    .shared_across = ..some(.value = &thread),
    .size = 32 * 1024,       // 32 KB per thread.
    .latency = 1,
    .access_mode = "Read-Write",
)

shared_memory : ParallelMemory = (
    .name = "Shared Memory",
    .shared_across = ..some(.value = &block),
    .size = 48 * 1024,       // 48 KB per block.
    .latency = 10,
    .access_mode = "Read-Write",
)

global_memory : ParallelMemory = (
    .name = "Global Memory",
    .shared_across = ..some(.value = &grid),
    .size = 8 * 1024 * 1024 * 1024, // 8 GB global memory
    .latency = 400,
    .access_mode = "Read-Write",
)

// Operations

matrix_multiply : ParallelOperation = (
    .name = "Matrix Multiply",
    .supported_by = ..some(.value = &block),    // Block-level operation.
    .supported_data_types = ("Float32", "Float64"),
    .latency = 20,
    .throughput = 1000000,
    .invocation_name = "matrix_mult",
    .native_implementation = "mma.sync",
)

vector_add : ParallelOperation = (
    .name = "Vector Add",
    .supported_by = ..some(.value = &thread),   // Thread-level operation.
    .supported_data_types = ("Int32", "Float32"),
    .latency = 5,
    .throughput = 10000000,
    .invocation_name = "vector_add",
    .native_implementation = "add.f32",
)

// Spec

cuda_spec : ParallelProcessingUnit = (
    .parallel_groups = (
        &block,
        &grid
    ),
    .memory_domains = (
        &registers,
        &shared_memory,
        &global_memory
    ),
    .operations = (
        &matrix_multiply,
        &vector_add
    ),
)
```

The compiler could use this information to choose implementations or tiling.

## Execution syntax sketch

> [!IDEA]
> One possible syntax for parallel execution, inspired by Mojo. This is
> pseudocode; it does not define the `kernel` or `parallel` keywords.

```text
kernel vector_add_kernel(
    executor: ParallelProcessingUnit,
    vector_a: Vector<Float32>,
    vector_b: Vector<Float32>
) -> (result: Vector<Float32>) {
    parallel for (i in executor.parallel_groups[0]) {
        result[i] = vector_a[i] + vector_b[i]
    }
}

config = ExecutionConfig(
    processing_unit = cuda_spec,
    grid_dim = (4, 4),
    block_dim = (16, 16)
)

executor = KernelExecutor(config)
output_matrix = executor|run(vector_add_kernel, input_matrix_a, input_matrix_b)
```

It might be better to avoid requiring keywords such as `kernel` and `parallel`.

## Device operations to account for

CUDA exposes operations and indices such as these. They are examples of
capabilities a device abstraction might need to represent:

```
cudamalloc()
cudamemcpy()  -- Host to device, device to host, or device to device.
cudafree()

-- To get the index of the thread
threadIdx.x

-- To get the index of the block
blockIdx.x

-- To get the size of the block
blockDim.x

-- To get the size of the grid
gridDim.x

-- To send kernel to GPU
my_kernel<<<grid_size, block_size>>>(args) -- grid_size in blocks, block_size in threads

```

The CPU could also be modeled this way to account for cache levels and thread
interaction. Whether the common model would justify its complexity remains
open.

## Research references

- [Parallel computing talk](https://www.youtube.com/watch?v=9-DiGrnz8l8)
  and [GPU programming talk](https://www.youtube.com/watch?v=Cak8ASX7NOk).
- [Mojo syntax discussion](https://github.com/modular/max/issues/1255).
- [Chris Lattner interview on parallel programming](https://youtu.be/JRcXUuQYR90?si=hdGrkURBEJcuNw_S&t=3952).

CUDA, Mojo, Triton, Julia, and XLA are useful comparison points for execution
and tiling models.
