-- Scheduling is independent of I/O capabilities. The erased ABI transports
-- only audited plain data; typed packaging and extraction remain in async/await.
_TaskEntry(.input: UIntNative, .output: UIntNative) -> (): CFunctionPointer(.isolated = true)

-- Entry, layout and source are one authenticated request. Providers can forward
-- it, but cannot change an entry's buffer bounds or retain the source borrow.
TaskRequest := (
    ._entry: _TaskEntry, ._input: &Any,
    ._input_size: UIntNative, ._output_size: UIntNative,
    ._input_alignment: UIntNative, ._output_alignment: UIntNative
)

Executor#(.Provider: Type): Contract = (
    .submit: (
        .self: $&Provider, .request: TaskRequest
    ) -> (.result: Errable#(TaskReceipt, (..task_start_failed))) where {
        on result ..ok { owns(result) depends_on(result, self) }
        on result ..error {}
    }
)

_task_create(
    .entry: _TaskEntry, .input: UIntNative, .input_size: UIntNative,
    .output_size: UIntNative, .input_alignment: UIntNative, .output_alignment: UIntNative
) -> (.handle: UIntNative): CFunction(.symbol = "_argi_task_create_buffers")

_task_join(.handle: UIntNative, .size: UIntNative) -> (.address: UIntNative): CFunction(
    .symbol = "_argi_task_join_result"
)
_task_destroy(.handle: UIntNative) -> (.status: CInt): CFunction(
    .symbol = "_argi_task_destroy"
)

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
    ._entry: _TaskEntry
)
implement Deinit#(TaskReceipt) (
    .deinit = (.self: $&TaskReceipt) -> () {
        assume ffi := self&._ffi
        if _task_destroy(.handle = self&._handle) != 0 { abort }
    }
)

implement Executor#(ThreadedExecutor) (
    .submit = (
        .self: $&ThreadedExecutor, .request: TaskRequest
    ) -> (.result: Errable#(TaskReceipt, (..task_start_failed))) {
        assume ffi := self&._ffi
        handle ::= _task_create(
            .entry = request._entry,
            .input = [request._input | convert#(.to: UIntNative)(_)],
            .input_size = request._input_size, .output_size = request._output_size,
            .input_alignment = request._input_alignment,
            .output_alignment = request._output_alignment
        )
        if handle == 0 {
            result = ..error(.reason = ..task_start_failed)
            return
        }
        result = ..ok(._handle = handle, ._ffi = self&._ffi, ._entry = request._entry)
    }
)

_task_result_address := (.task: &TaskReceipt, .size: UIntNative) -> (.address: UIntNative) {
    assume ffi := task&._ffi
    address = _task_join(.handle = task&._handle, .size = size)
}
