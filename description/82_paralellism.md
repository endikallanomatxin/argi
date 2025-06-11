### Parallelism / GPU

<iframe width="560" height="315" src="https://www.youtube.com/embed/9-DiGrnz8l8?si=xdX92FK0uv8cYoaa" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>
<iframe width="560" height="315" src="https://www.youtube.com/embed/Cak8ASX7NOk?si=nvnwLH70aVcLUqSz" title="YouTube video player" frameborder="0" allow="accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share" referrerpolicy="strict-origin-when-cross-origin" allowfullscreen></iframe>

Fijarse en: cuda, mojo, triton, julia...

XLA es un compilador para álgebra lineal en gpus.

Crítica a sintaxis de mojo. https://github.com/modular/max/issues/1255

Handle shared memory hierarchy in GPUs (L0, L1, L2...)

Tiling programming languges.
[Entrevista Chris Latner](https://youtu.be/JRcXUuQYR90?si=hdGrkURBEJcuNw_S&t=3952)
Hay hardware accelerated small matrix multiplication. Para aprovechar eso, tiling.

```mojo
@kernel
def vector_add(A: list[float], B: list[float], C: list[float], N: int):
    for i in parallel(0:N):  # Bucle paralelo
        C[i] = A[i] + B[i]
```

Para nuestro idioma.

Podríamos definir una Spec de una gráfica de la siguiente manera:

Tipos parte 

```
ParallelProcessingUnit : Type = struct [
    .parallel_groups: list[ParallelGroup]
    .memory_domains: list[ParallelMemory]
    .operations: list[ParallelOperation]
]

ParallelGroup : Type = struct [
    .name: string
    .groups: ?ParallelGroup
    .number: int
]

ParallelMemory : Type = struct [
    .name: string
    .shared_across: ?ParallelGroup
    .size: int
    .latency: int
    .access_mode: string
]

ParallelOperation : Type = struct [
    .name: string
    .supported_by: ?ParallelGroup
    .supported_data_types: list[string]
    .latency: int
    .throughput: int
    .invocation_name: string
    .native_implementation: string
]

thread : ParallelGroup = [
    .name="Thread",
    .groups=nil,        // No tiene agrupación abstractior
    .number=1           // Cada thread es independiente
]


// Cuda Example

// Parallel Groups

block : ParallelGroup = [
    .name="Block",
    .groups=&THREAD,       // Bloques contienen threads
    .number=16             // 16 threads por bloque
]

grid : ParallelGroup = [
    .name="Grid",
    .groups=&block,  // Grid contiene bloques
    .number=4              // 4 bloques por grid
]

// Memory Domains

registers : ParallelMemory = [
    .name="Registers",
    .sharedAcross=&THREAD,
    .size=32 * 1024,       // 32 KB por thread
    .latency=1,
    .accessMode="Read-Write"
]

shared_memory : ParallelMemory = [
    .name="Shared Memory",
    .sharedAcross=&block,
    .size=48 * 1024,       // 48 KB por bloque
    .latency=10,
    .accessMode="Read-Write"
)

global_memory : ParallelMemory = [
    .name="Global Memory",
    .sharedAcross=&grid,
    .size=8 * 1024 * 1024 * 1024, // 8 GB globales
    .latency=400,
    .accessMode="Read-Write"
]

// Operations

matrix_multiply : ParallelOperation = [
    .name="Matrix Multiply",
    .supportedBy=&block,      // Operación a nivel de bloque
    .supportedDataTypes=["Float32", "Float64"],
    .latency=20,
    .throughput=1000000,
    .invocationName="matrix_mult",
    .nativeImplementation="mma.sync"
]

vector_add : ParallelOperation = [
    .name="Vector Add",
    .supportedBy=&THREAD,     // Operación a nivel de thread
    .supportedDataTypes=["Int32", "Float32"],
    .latency=5,
    .throughput=10000000,
    .invocationName="vector_add",
    .nativeImplementation="add.f32"
]

// Spec

cuda_spec : ParallelProcessingUnit = [
    .parallel_groups=[
        &block,
        &grid
    ],
    .memory_domains=[
        &registers,
        &shared_memory,
        &global_memory
    ],
    .operations=[
        &matrix_multiply,
        &vector_add
    ]
]
```

Y en base a eso el lenguaje optimiza ejecución.

Propuesta de ejemplo de uso inspirado en mojo:

```
kernel vector_add_kernel(
		executor: ParallelProcessingUnit
		vector_a: Vector<Float32>,
		vector_b: Vector<Float32>
	) -> (
		result: Vector<Float32>  // Si la variable está nombrada arriba, 
	)
    parallel for (i in executor.parallel_groups[0])
        result[i] = vector_a[i] + vector_b[i]

config = ExecutionConfig(
    processing_unit=cuda_spec,
    grid_dim=[4, 4],     // Configuración de grids
    block_dim=[16, 16]   // Configuración de bloques
)

executor = KernelExecutor(config)
output_matrix = executor|run(vector_add_kernel, input_matrix_a, input_matrix_b)
```

Igual estaría bien que no hubiera que usar palabras reservadas como kernel y parallel.

Things used in cuda:

```
cudamalloc()
cudamemcpy()  -- Hay host to device, device to host, device to device
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

Igual también se puede modelizar así la CPU para tener en cuenta los distintos niveles de cache o interacción entre hilos. Aunque no se yo si es necesario o aporta mucho. Al final la gracia es que como es simple se hace solo.

