Empty: Type = ()

main := () -> (.status_code: Int32) {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate<.t: Empty>(.self = $&allocator, .count = 0)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            slot ::= allocation_slot<.t: Empty>(.allocation = &memory, .index = 0).slot
        }
    }
    status_code = 42
}
