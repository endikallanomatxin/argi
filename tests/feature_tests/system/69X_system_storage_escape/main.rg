EntryStorage := (
    .ffi            : ForeignFunctionInterface
    .memory         : Memory
    .page_allocator : PageAllocator
    .terminal       : Terminal
    .args           : Arguments
    .env_vars       : EnvironmentVariables
    .file_system    : FileSystem
    .network        : Network
    .proc_man       : ProcessManager
    .clock          : Clock
    .rand_gen       : RandomNumberGenerator
)

initialize_system := (.storage: $&EntryStorage, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .system : System
) {
    assume error_tracer
    storage&.ffi = ForeignFunctionInterface()
    assume ffi ::= $&storage&.ffi
    storage&.memory = Memory()
    storage&.page_allocator = PageAllocator(.memory = $&storage&.memory)
    storage&.terminal = Terminal()
    storage&.args = Arguments()
    storage&.env_vars = EnvironmentVariables()
    storage&.file_system = FileSystem()
    storage&.network = Network()
    storage&.proc_man = ProcessManager()
    storage&.clock = Clock()
    storage&.rand_gen = RandomNumberGenerator()
    system = (
        .ffi            = $&storage&.ffi
        .memory         = $&storage&.memory
        .page_allocator = $&storage&.page_allocator
        .terminal       = $&storage&.terminal
        .args           = $&storage&.args
        .env_vars       = $&storage&.env_vars
        .file_system    = $&storage&.file_system
        .network        = $&storage&.network
        .proc_man       = $&storage&.proc_man
        .clock          = $&storage&.clock
        .rand_gen       = $&storage&.rand_gen
    )
}

escape_system := (.error_tracer: $&Virtual#(ErrorTracer)) -> (.system: System) {
    assume error_tracer
    storage :: EntryStorage
    system = initialize_system(.storage = $&storage)
}

main := () -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    system ::= escape_system()
    status_code = 42
}
