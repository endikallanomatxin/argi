-- The handle owns native stable buffers. Moving this owner moves no task bytes.
-- Its executor borrow must remain live until join and physical destruction.
Future := #(.T: Type) (
    ._task: TaskReceipt
)

implement#(.T: Type) Deinit#(Future#(T)) (
    .deinit = (.self: $&Future#(T)) -> () {
        #if is_plain_data(.type = T) {
            deinit(.self = $&self&._task)
        } #else {
            _close_task(.self = $&self&._task)
            output: _OwnedTaskOutput#(T) = (._slot = self&._task._output_slot, ._entry = self&._task._entry, ._ffi = self&._task._ffi)
        }
    }
)

-- The native adapter keeps both aligned buffers live for this entire callback.
-- Local anchors bound these trusted borrows to that callback, not to an
-- arbitrary foreign address. Input reference leaves are checked at submission.
_task_worker := #(.F: Function) (.invocation: _ExecutionInvocation) -> (.cleanup: _TaskResultCleanup): CFunction {
    anchor: UInt8 = 0
    root ::= erase_reference#(UInt8)(.base = &anchor)
    input_ref ::= _execution_input#(inputs_of#(F))(.invocation = invocation, .anchor = root)
    args ::= input_ref&
    value ::= invoke#(F)(.args = ~args)
    _initialize_task_output#(result_of#(F))(.invocation = invocation, .value = ~value)
    cleanup = zeroed#(.t: _TaskResultCleanup)()
}

_owned_task_worker := #(.F: Function) (.invocation: _ExecutionInvocation) -> (.cleanup: _TaskResultCleanup): CFunction {
    anchor: UInt8 = 0
    root ::= erase_reference#(UInt8)(.base = &anchor)
    slot ::= _execution_input#(inputs_of#(F))(.invocation = invocation, .anchor = root)
    -- Only the authenticated, accepted invocation can take this input.
    args ::= trusted_opaque_move_out#(.t: inputs_of#(F), .storage_type: UInt8)(.storage = $&anchor, .slot = slot)
    value ::= invoke#(F)(.args = ~args)
    _initialize_task_output#(result_of#(F))(.invocation = invocation, .value = ~value)
    cleanup = zeroed#(.t: _TaskResultCleanup)()
}

async := #(.F: Function) (
    .args: inputs_of#(F), .executor: Virtual#(Executor)
) -> (.result: Errable#(Future#(result_of#(F)), (..task_start_failed, ..unsupported_task_value, ..executor_mismatch))) {
    prepared ::= ~args
    #if is_borrowable_data(.type = inputs_of#(F)) and is_plain_data(.type = result_of#(F)) {
        entry ::= _TaskEntry(.function = _task_worker#(F))
        request ::= _prepare_task_request#(F)(.entry = entry, .output_slot = 0,
            .input = erase_reference#(inputs_of#(F))(.base = &prepared), .access = _execution_lend(.inputs = prepared))
        output_slot ::= request._output_slot
        task ::= Executor#().submit(.self = $&executor, .request = ~request)!
        -- A provider cannot substitute a task with a different typed worker.
        -- The private entry comes from the authenticated native submission.
        if task._entry != entry or task._output_slot != output_slot {
            result = ..error(.reason = ..executor_mismatch)
            return
        }
        result = ..ok(._task = ~task)
    } #else {
        -- Unsupported payloads never instantiate a worker or enter native code.
        result = ..error(.reason = ..unsupported_task_value)
    }
}

_prepare_task_request := #(.F: Function) (
    .entry: _TaskEntry, .output_slot: UIntNative, .input: &Any, .access: _ExecutionReceipt
) -> (.result: TaskRequest) {
    result = (
        ._output_slot = output_slot, ._entry = entry, ._input = input,
        ._input_size = size_of(.type = inputs_of#(F)),
        ._output_size = size_of(.type = result_of#(F)),
        ._input_alignment = alignment_of(.type = inputs_of#(F)),
        ._output_alignment = alignment_of(.type = result_of#(F)),
        ._access = ~access
    )
}

-- Retire the sender only after the native adapter authenticates acceptance.
_retire_task_input := #(.T: Type) (.value: T) -> () {
    -- The authenticated native slot has transferred this input to its worker.
    -- Moving the local value into this sink clears its cleanup without a drop.
}

_require_task_input_transfer := #(.T: Type) (.value: &T) -> () {}

-- Submit a moved input with static transfer evidence and a plain result.
async_owned := #(.F: Function) (
    .args: inputs_of#(F), .executor: Virtual#(Executor), .ffi: $&ForeignFunctionInterface
) -> (.result: Errable#(Future#(result_of#(F)), (..task_start_failed, ..executor_mismatch, ..unsupported_task_value))) {
    #if is_plain_data(.type = result_of#(F)) == false {
        result = ..error(.reason = ..unsupported_task_value)
        return
    }

    prepared: inputs_of#(F) = ~args
    _require_task_input_transfer#(inputs_of#(F))(.value = &prepared)
    entry ::= _TaskEntry(.function = _owned_task_worker#(F))
    output ::= _prepare_task_output#(result_of#(F))(.entry = entry, .ffi = ffi)!
    request ::= _prepare_task_request#(F)(.entry = entry, .output_slot = output._slot,
        .input = erase_reference#(inputs_of#(F))(.base = &prepared), .access = _execution_lend(.inputs = prepared))
    submitted ::= Executor#().submit(.self = $&executor, .request = ~request)
    accepted ::= _task_output_accepted(.slot = output._slot, .entry = entry, .ffi = ffi).accepted != 0
    if accepted { _retire_task_input#(inputs_of#(F))(.value = ~prepared) }
    match submitted {
        ..error _ { result = ..error(.reason = ..task_start_failed) }
        ..ok ~task {
            if accepted == false { abort }
            if task._entry != entry or task._output_slot != output._slot {
                result = ..error(.reason = ..executor_mismatch)
                return
            }
            #if is_plain_data(.type = result_of#(F)) {
                if _detach_task_output(.slot = output._slot, .task = task._handle, .entry = entry, .ffi = ffi) != 0 { abort }
                task._output_slot = 0
            } #else {
                output._slot = 0
            }
            result = ..ok(._task = ~task)
        }
    }
}

await := #(.T: Type) (.self: $&Future#(T)) -> (
    .result: Errable#(T, (..already_awaited, ..task_join_failed))
) {
    if self&._task._result_taken {
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
        self&._task._result_taken = true
        result = ..ok ~value
    } #else {
        if _execution_reclaim_native(.handle = self&._task._handle, .ffi = self&._task._ffi) != 0 {
            result = ..error(.reason = ..task_join_failed)
            return
        }
        _close_task(.self = $&self&._task)
        self&._task._result_taken = true
        output: _OwnedTaskOutput#(T) = (._slot = self&._task._output_slot, ._entry = self&._task._entry, ._ffi = self&._task._ffi)
        self&._task._output_slot = 0
        value ::= _take_task_output#(T)(.self = $&output)
        result = ..ok ~value
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
