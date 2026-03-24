System : Type = (
  .allocator : $&CAllocator
  .terminal  : $&Terminal
  .args      : $&Arguments
  .env_vars  : $&EnvironmentVariables
  .file_sys  : $&FileSystem
  .network   : $&Network
  .proc_man  : $&ProcessManager
  .clock     : $&Clock
  .rand_gen  : $&RandomNumberGenerator
  .ffi       : $&ForeignFunctionInterface
)

allocate_runtime_value#(.t: Type)() -> (.ptr: $&t) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size_of(.type = t)))
    ptr = cast#(.to: $&t)(.value = raw_addr)
}

init(.p: $&System) -> () := {
    allocator_ptr ::= allocate_runtime_value#(.t = CAllocator)()
    stdin_ptr ::= allocate_runtime_value#(.t = StdIn)()
    stdout_ptr ::= allocate_runtime_value#(.t = StdOut)()
    stderr_ptr ::= allocate_runtime_value#(.t = StdErr)()
    terminal_ptr ::= allocate_runtime_value#(.t = Terminal)()
    args_ptr ::= allocate_runtime_value#(.t = Arguments)()
    env_vars_ptr ::= allocate_runtime_value#(.t = EnvironmentVariables)()
    file_sys_ptr ::= allocate_runtime_value#(.t = FileSystem)()
    network_ptr ::= allocate_runtime_value#(.t = Network)()
    proc_man_ptr ::= allocate_runtime_value#(.t = ProcessManager)()
    clock_ptr ::= allocate_runtime_value#(.t = Clock)()
    rand_gen_ptr ::= allocate_runtime_value#(.t = RandomNumberGenerator)()
    ffi_ptr ::= allocate_runtime_value#(.t = ForeignFunctionInterface)()

    init(.p = allocator_ptr)
    init(.p = terminal_ptr, .stdin = stdin_ptr, .stdout = stdout_ptr, .stderr = stderr_ptr)

    p& = (
        .allocator = allocator_ptr,
        .terminal = terminal_ptr,
        .args = args_ptr,
        .env_vars = env_vars_ptr,
        .file_sys = file_sys_ptr,
        .network = network_ptr,
        .proc_man = proc_man_ptr,
        .clock = clock_ptr,
        .rand_gen = rand_gen_ptr,
        .ffi = ffi_ptr
    )
}
