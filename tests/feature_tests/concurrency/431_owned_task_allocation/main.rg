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
    recover_ordinary(.owner = $&allocator)
    if shared_load(.self = counter) != 1 { abort }
    recover_ordinary(.owner = $&releases)
}
