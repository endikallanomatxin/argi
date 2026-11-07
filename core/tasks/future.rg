-- The handle owns native stable buffers. Moving this owner moves no task bytes.
-- Its executor borrow must remain live until join and physical destruction.
Future := #(.T: Type) (
    ._task: TaskReceipt,
    ._taken: Bool = false
)

implement#(.T: Type) Deinit#(Future#(T)) (
    .deinit = (.self: $&Future#(T)) -> () {
        deinit(.self = $&self&._task)
    }
)

-- The native adapter keeps both aligned buffers live for this entire callback.
-- Local anchors bound these trusted borrows to that callback, not to an
-- arbitrary foreign address. Input reference leaves are checked at submission.
_task_worker := #(.F: Function) (.invocation: _ExecutionInvocation) -> (): CFunction {
    anchor: UInt8 = 0
    root ::= erase_reference#(UInt8)(.base = &anchor)
    input_ref ::= _execution_input#(inputs_of#(F))(.invocation = invocation, .anchor = root)
    args ::= input_ref&
    value ::= invoke#(F)(.args = ~args)
    if invocation._output == 0 or
        invocation._output_size != size_of(.type = result_of#(F)) or
        invocation._output_alignment != alignment_of(.type = result_of#(F)) or
        invocation._output % alignment_of(.type = result_of#(F)) != 0 { abort }
    output_ref ::= trusted_establish_inherited_reference#(result_of#(F))(
        .raw = raw_pointer#(result_of#(F))(.address = invocation._output), .root = root
    )
    output_ref&= ~value
}

async := #(.F: Function) (
    .args: inputs_of#(F), .executor: Virtual#(Executor)
) -> (.result: Errable#(Future#(result_of#(F)), (..task_start_failed, ..unsupported_task_value, ..executor_mismatch))) {
    prepared ::= ~args
    #if is_borrowable_data(.type = inputs_of#(F)) and is_plain_data(.type = result_of#(F)) {
        entry ::= _TaskEntry(.function = _task_worker#(F))
        request: TaskRequest = (
            ._entry = entry, ._input = erase_reference#(inputs_of#(F))(.base = &prepared),
            ._input_size = size_of(.type = inputs_of#(F)),
            ._output_size = size_of(.type = result_of#(F)),
            ._input_alignment = alignment_of(.type = inputs_of#(F)),
            ._output_alignment = alignment_of(.type = result_of#(F)),
            ._access = _execution_lend(.inputs = prepared)
        )
        task ::= Executor#().submit(.self = $&executor, .request = ~request)!
        -- A provider cannot substitute a task with a different typed worker.
        -- The private entry comes from the authenticated native submission.
        if task._entry != entry {
            result = ..error(.reason = ..executor_mismatch)
            return
        }
        result = ..ok(._task = ~task, ._taken = false)
    } #else {
        -- Unsupported payloads never instantiate a worker or enter native code.
        result = ..error(.reason = ..unsupported_task_value)
    }
}

await := #(.T: Type) (.self: $&Future#(T)) -> (
    .result: Errable#(T, (..already_awaited, ..task_join_failed))
) {
    if self&._taken {
        result = ..error(.reason = ..already_awaited)
        return
    }
    #if is_plain_data(.type = T) {
        result_size ::= size_of(.type = T)
        address ::= _task_result_address(.task = $&self&._task, .size = result_size)
        if address == 0 {
            result = ..error(.reason = ..task_join_failed)
            return
        }
        _execution_complete(.receipt = $&self&._task._access,
            .join = ..some(.value = (._handle = self&._task._handle, ._ffi = self&._task._ffi)))
        value ::= _copy_plain_task_result#(
            .T: T,
            .N = #run () -> (.size: UIntNative) { size = size_of(.type = T) }
        )(.task = &self&._task)!
        self&._taken = true
        result = ..ok ~value
    } #else {
        result = ..error(.reason = ..task_join_failed)
    }
}

-- A zero-length array carries T's alignment without constructing a T. The
-- initialized byte array starts at offset zero and has exactly T's byte size.
_TaskResultStorage := #(.T: Type, .N: UIntNative) (
    ._alignment: [0]T, ._bytes: [N]UInt8
)

_copy_plain_task_result := #(.T: Type, .N: UIntNative) (.task: &TaskReceipt) -> (
    .result: Errable#(T, (..task_join_failed))
) {
    if N != size_of(.type = T) { abort }
    storage: _TaskResultStorage#(T, N) = (._alignment = (), ._bytes = zeroed#([N]UInt8)())
    offset :: UIntNative = 0
    while offset < N {
        block ::= _read_task_result_block(.task = task, .offset = offset)
        if block._count == 0 or block._count > 32 or block._count > N - offset {
            result = ..error(.reason = ..task_join_failed)
            return
        }
        index :: UIntNative = 0
        while index < block._count {
            storage._bytes[offset + index] = block._bytes[index]
            index = index + 1
        }
        offset = offset + block._count
    }
    -- Only plain results instantiate this helper. Every byte came from the
    -- matching typed worker after join, including aggregate representation.
    value ::= trusted_reinterpret_reference#(.from: [N]UInt8, .to: T)(.base = &storage._bytes)
    result = ..ok value&
}
