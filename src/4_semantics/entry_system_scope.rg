-- Resources belong to the enclosing checked entry scope.
-- This fragment installs no user-facing writer or allocator assumptions.
    ffi_storage ::= ForeignFunctionInterface()
    assume ffi ::= $&ffi_storage
    memory_storage ::= Memory()
    page_allocator_storage ::= PageAllocator(.memory = $&memory_storage)

    terminal_storage ::= Terminal()
    terminal ::= $&terminal_storage
    args_storage ::= Arguments()
    env_vars_storage ::= EnvironmentVariables()
    file_system_storage ::= FileSystem()
    network_storage ::= Network()
    proc_man_storage ::= ProcessManager()
    clock_storage ::= Clock()
    rand_gen_storage ::= RandomNumberGenerator()

    system :: System = (
        .memory         = $&memory_storage,
        .page_allocator = $&page_allocator_storage,
        .terminal       = terminal,
        .args           = $&args_storage,
        .env_vars       = $&env_vars_storage,
        .file_system    = $&file_system_storage,
        .network        = $&network_storage,
        .proc_man       = $&proc_man_storage,
        .clock          = $&clock_storage,
        .rand_gen       = $&rand_gen_storage,
        .ffi            = $&ffi_storage,
    )
