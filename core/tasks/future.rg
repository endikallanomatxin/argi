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
_task_worker := #(.F: Function) (.input: UIntNative, .output: UIntNative) -> (): CFunction {
    anchor: UInt8 = 0
    root ::= erase_reference#(UInt8)(.base = &anchor)
    input_ref ::= _execution_input#(inputs_of#(F))(.address = input, .anchor = root)
    args ::= input_ref&
    value ::= invoke#(F)(.args = ~args)
    output_ref ::= trusted_establish_inherited_reference#(result_of#(F))(
        .raw = raw_pointer#(result_of#(F))(.address = output), .root = root
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
        address ::= _task_result_address(.task = $&self&._task, .size = size_of(.type = T))
        if address == 0 {
            result = ..error(.reason = ..task_join_failed)
            return
        }
        _execution_complete(.receipt = $&self&._task._access)
        output ::= trusted_establish_inherited_reference#(T)(
            .raw = raw_pointer#(T)(.address = address),
            .root = erase_mutable_reference#(Future#(T))(.base = self)
        )
        value ::= output&
        self&._taken = true
        result = ..ok ~value
    } #else {
        result = ..error(.reason = ..task_join_failed)
    }
}
