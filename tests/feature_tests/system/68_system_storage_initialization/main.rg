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

initialize_storage := (.storage: $&EntryStorage) -> () {
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
}

main := () -> (.status_code: Int32) {
    storage :: EntryStorage
    initialize_storage(.storage = $&storage)
    page_virtual ::= to_virtual#(Allocator)($&storage.page_allocator)
    system :: System
    system = (
        .ffi            = $&storage.ffi
        .memory         = $&storage.memory
        .page_allocator = $&page_virtual
        .terminal       = $&storage.terminal
        .args           = $&storage.args
        .env_vars       = $&storage.env_vars
        .file_system    = $&storage.file_system
        .network        = $&storage.network
        .proc_man       = $&storage.proc_man
        .clock          = $&storage.clock
        .rand_gen       = $&storage.rand_gen
    )
    if storage.page_allocator.page_size == 0 { abort }
    status_code = 42
}
