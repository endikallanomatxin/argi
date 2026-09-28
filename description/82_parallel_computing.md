### Parallel computing / GPU

<iframe width="560" height="315" src="https://www.youtube.com/embed/9-DiGrnz8l8?si=xdX92FK0uv8cYoaa" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
<iframe width="560" height="315" src="https://www.youtube.com/embed/Cak8ASX7NOk?si=nvnwLH70aVcLUqSz" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

Look at CUDA, Mojo, Triton, Julia, and others.

XLA is a compiler for linear algebra on GPUs.

Criticism of Mojo syntax: https://github.com/modular/max/issues/1255

Handle shared memory hierarchy in GPUs (L0, L1, L2...)

Tiling programming languges.
[Entrevista Chris Latner](https://youtu.be/JRcXUuQYR90?si=hdGrkURBEJcuNw_S&t=3952)
Small matrix multiplication can be hardware-accelerated. Use tiling to take advantage of this.

```mojo
@kernel
def vector_add(A: list[float], B: list[float], C: list[float], N: int):
    for i in parallel(0:N):  # Parallel loop
        C[i] = A[i] + B[i]
```

For our language.

We could define a specification for a graph as follows:

Partial type definitions

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
    .size = 8 * 1024 * 1024 * 1024, // 8 GB globales
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

The language can optimize execution based on this information.

> [!IDEA]
> One possible syntax for parallel execution, inspired by Mojo:

```
kernel vector_add_kernel(
		executor: ParallelProcessingUnit
		vector_a: Vector<Float32>,
		vector_b: Vector<Float32>
	) -> (
		result: Vector<Float32>  // If the variable is named above,
	)
    parallel for (i in executor.parallel_groups[0])
        result[i] = vector_a[i] + vector_b[i]

config = ExecutionConfig(
    processing_unit = cuda_spec,
    grid_dim = (4, 4),     // Grid dimensions
    block_dim = (16, 16)   // Block dimensions
)

executor = KernelExecutor(config)
output_matrix = executor|run(vector_add_kernel, input_matrix_a, input_matrix_b)
```

It might be better to avoid requiring keywords such as `kernel` and `parallel`.

Things used in cuda:

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
interaction. It is unclear whether this is necessary or adds much; the main
benefit is that the model is simple to implement.
