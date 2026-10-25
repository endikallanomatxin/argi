Empty: Type = ()

main() -> (.status_code: Int32) := {
    assume ffi ::= $&ForeignFunctionInterface()
    assume error_tracer ::= $&noop_error_tracer
    allocator ::= CAllocator(.ffi = ffi)
    allocated ::= allocate_bytes(.self = $&allocator, .size = 16)
    match allocated {
        ..error _ { abort }
        ..ok ~payload {
            memory ::= ~payload
            slot ::= allocation_slot#(.t: Empty)(.allocation = &memory, .index = 0).slot
        }
    }
    status_code = 42
}
