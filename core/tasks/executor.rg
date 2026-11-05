-- Scheduling is independent of I/O capabilities. The erased ABI transports
-- audited inputs and plain results; typed packaging remains in async/await.
_TaskEntry(.input: UIntNative, .output: UIntNative) -> (): CFunctionPointer(.isolated = true)

-- Entry, layout and source are one authenticated request. Providers can forward
-- it, but cannot change an entry's buffer bounds or retain the source borrow.
TaskRequest := (
    ._entry: _TaskEntry, ._input: &Any,
    ._input_size: UIntNative, ._output_size: UIntNative,
    ._input_alignment: UIntNative, ._output_alignment: UIntNative,
    ._access: _ExecutionReceipt
)

-- A request that was never accepted has no native execution to join. On
-- success its receipt moves into the returned task before request cleanup.
implement Deinit#(TaskRequest) (
    .deinit = (.self: $&TaskRequest) -> () {
        deinit(.self = $&self&._access)
    }
)

Executor#(.Provider: Type): Contract = (
    .submit: (
        .self: $&Provider, .request: TaskRequest
    ) -> (.result: Errable#(TaskReceipt, (..task_start_failed))) where {
        on result ..ok { owns(result) depends_on(result, self) carries_execution(result, request) }
        on result ..error { completes_execution(request) }
    }
)

-- Audited native footprints describe synchronous access to Argi storage. The
-- initial copy reads the source buffer; join and destroy touch only private
-- runtime storage. Worker access remains governed by the execution receipt.
_task_create(
    .entry: _TaskEntry, .input: &Any, .input_size: UIntNative,
    .output_size: UIntNative, .input_alignment: UIntNative, .output_alignment: UIntNative
) -> (.handle: UIntNative): CFunction(.symbol = "_argi_task_create_buffers") where { reads(input) }

_task_join(.handle: UIntNative, .size: UIntNative) -> (.address: UIntNative): CFunction(
    .symbol = "_argi_task_join_result"
) where { no_access() }
_task_destroy(.handle: UIntNative) -> (.status: CInt): CFunction(
    .symbol = "_argi_task_destroy"
) where { no_access() }

ThreadedExecutor := (._ffi: $&ForeignFunctionInterface)
ThreadedExecutorInitArgs: Type = (.ffi: $&ForeignFunctionInterface)
implement Init#(ThreadedExecutor, ThreadedExecutorInitArgs) (
    .Result: Type = ThreadedExecutor
    .init = ThreadedExecutorInitArgs -> (.result: ThreadedExecutor) {
        result = (._ffi = ffi)
    }
)

-- The receipt cannot be fabricated outside bundled core. Its private handle
-- and FFI dependency are established only after the native adapter owns a task.
TaskReceipt := (
    ._handle: UIntNative, ._ffi: $&ForeignFunctionInterface,
    ._entry: _TaskEntry, ._access: _ExecutionReceipt = (._marker = 0)
)
implement Deinit#(TaskReceipt) (
    .deinit = (.self: $&TaskReceipt) -> () {
        assume ffi := self&._ffi
        if _task_destroy(.handle = self&._handle) != 0 { abort }
        _execution_complete(.receipt = $&self&._access)
    }
)

implement Executor#(ThreadedExecutor) (
    .submit = (
        .self: $&ThreadedExecutor, .request: TaskRequest
    ) -> (.result: Errable#(TaskReceipt, (..task_start_failed))) {
        pending ::= ~request
        assume ffi := self&._ffi
        handle ::= _task_create(
            .entry = pending._entry,
            .input = pending._input,
            .input_size = pending._input_size, .output_size = pending._output_size,
            .input_alignment = pending._input_alignment,
            .output_alignment = pending._output_alignment
        )
        if handle == 0 {
            result = ..error(.reason = ..task_start_failed)
            return
        }
        _execution_accept(.receipt = $&pending._access)
        result = ..ok(
            ._handle = handle, ._ffi = self&._ffi, ._entry = pending._entry,
            ._access = ~pending._access
        )
    }
)

_task_result_address := (.task: $&TaskReceipt, .size: UIntNative) -> (.address: UIntNative) {
    assume ffi := task&._ffi
    address = _task_join(.handle = task&._handle, .size = size)
}
