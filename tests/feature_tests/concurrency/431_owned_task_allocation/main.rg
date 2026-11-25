storage := import("./provider")

set_first_byte := (.allocation: &Allocation, .byte: UInt8) -> () {
    pointer ::= trusted_establish_allocation_slot#(UInt8)(
        .allocation = allocation, .slot = allocation&.data, .anchor = allocation&.anchor
    )
    pointer& = byte
}

mutate := (.value: Allocation) -> (.result: Allocation) {
    owned ::= ~value
    set_first_byte(.allocation = &owned, .byte = 8)
    result = ~owned
}

RejectingExecutor := (.ffi: $&ForeignFunctionInterface)
implement Executor#(RejectingExecutor) (
    .state = region(self)
    .submit = (.self: $&RejectingExecutor, .request: TaskRequest) -> (
        .result: Errable#(TaskReceipt, (..task_start_failed))
    ) {
        pending ::= ~request
        submitted ::= execute_inline(.request = ~pending, .ffi = self&.ffi)
        match submitted {
            ..ok ~receipt {}
            ..error _ { abort }
        }
        result = ..error(.reason = ..task_start_failed)
    }
)

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    releases ::= unwrap_or_abort(AtomicUInt32(.ffi = system.ffi, .initial = 0))
    counter ::= $$&releases
    allocator ::= storage.Provider(.ffi = system.ffi, .releases = counter)
    shared ::= $$&allocator
    {
        outbound ::= unwrap_or_abort(storage.allocate(.provider = shared, .ffi = system.ffi))
        returning ::= unwrap_or_abort(async_owned#(mutate)(.args = (.value = ~outbound), .executor = executor, .ffi = system.ffi))
        match await($&returning) {
            ..ok ~returned {
                held ::= ~returned
                pointer ::= trusted_establish_allocation_slot#(.t: UInt8)(
                    .allocation = &held, .slot = held.data, .anchor = held.anchor
                )
                if pointer& != 8 { abort }
                pointer& = 9
                if pointer& != 9 { abort }
            }
            ..error _ { abort }
        }
    }
    if shared_load(.self = counter) != 1 { abort }
    {
        rejecting ::= RejectingExecutor(.ffi = system.ffi)
        failure_executor ::= Virtual#(Executor)($&rejecting)
        outbound ::= unwrap_or_abort(storage.allocate(.provider = shared, .ffi = system.ffi))
        match async_owned#(mutate)(.args = (.value = ~outbound), .executor = failure_executor, .ffi = system.ffi) {
            ..ok ~unexpected { abort }
            ..error failure {
                if is(.value = failure.reason, .variant = ..task_start_failed) == false { abort }
            }
        }
    }
    recover_ordinary(.owner = $&allocator)
    if shared_load(.self = counter) != 2 { abort }
    recover_ordinary(.owner = $&releases)
}
