SystemStorage : Type = (
  .allocator : CAllocator
  .terminal  : Terminal
  .args      : Arguments
  .env_vars  : EnvironmentVariables
  .file_sys  : FileSystem
  .network   : Network
  .proc_man  : ProcessManager
  .clock     : Clock
  .rand_gen  : RandomNumberGenerator
  .ffi       : ForeignFunctionInterface
)

System : Type = (
  ._storage  : SystemStorage
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

once init(.p: $&System) -> () := {
    --
    -- Current runtime-backed initialization baseline:
    --
    -- - `allocator` starts from the process C allocator.
    -- - `terminal` wraps the preopened stdio streams exposed by the host
    --   runtime.
    -- - `args` snapshots `argc` / `argv` addresses from the runtime entrypoint.
    -- - `env_vars` and `ffi` are zero-state capability roots; they gain
    --   behavior through their operations rather than through stored runtime
    --   state.
    --
    p&._storage.allocator = CAllocator()
    p&._storage.terminal = Terminal(
        .allocator = $&p&._storage.allocator,
    )
    p&._storage.args = Arguments()
    p&._storage.env_vars = EnvironmentVariables()
    p&._storage.file_sys = FileSystem()
    p&._storage.network = Network()
    p&._storage.proc_man = ProcessManager()
    p&._storage.clock = Clock()
    p&._storage.rand_gen = RandomNumberGenerator()
    p&._storage.ffi = ForeignFunctionInterface()

    p&.allocator = $&p&._storage.allocator
    p&.terminal = $&p&._storage.terminal
    p&.args = $&p&._storage.args
    p&.env_vars = $&p&._storage.env_vars
    p&.file_sys = $&p&._storage.file_sys
    p&.network = $&p&._storage.network
    p&.proc_man = $&p&._storage.proc_man
    p&.clock = $&p&._storage.clock
    p&.rand_gen = $&p&._storage.rand_gen
    p&.ffi = $&p&._storage.ffi
}

deinit(.self: $$&System) -> () := {
    deinit(.self = $$&self&._storage.terminal)
}
