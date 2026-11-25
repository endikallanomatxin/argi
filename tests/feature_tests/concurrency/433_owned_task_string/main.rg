forward := (.text: String) -> (.result: String) { result = ~text }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    {
        local ::= unwrap_or_abort(string_with_length(.allocator = Virtual#(Allocator)($&allocator), .length = 3))
        if byte_length(.self = &local) != 3 { abort }
    }
    shared ::= $$&allocator
    text ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    selected :: String
    if byte_length(.self = &text) == 3 { selected = ~text } else { selected = ~text }
    forwarded ::= forward(.text = ~selected)
    {
        task ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~forwarded), .executor = executor, .ffi = system.ffi))
        outcome ::= await($&task)
        match outcome {
            ..ok ~returned {
                owned :: String = ~returned
                _ = unwrap_or_abort(set_ascii(.self = $&owned, .index = 2, .byte = 66))
                if unwrap_or_abort(bytes_get(.view = &owned, .index = 2)) != 66 { abort }
                again ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~owned), .executor = executor, .ffi = system.ffi))
                twice_returned ::= unwrap_or_abort(await($&again))
                if unwrap_or_abort(bytes_get(.view = &twice_returned, .index = 2)) != 66 { abort }
            }
            ..error _ { abort }
        }
    }
    {
        unreturned ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
        discarded_task ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~unreturned), .executor = executor, .ffi = system.ffi))
        -- Dropping the future joins and destroys the unclaimed String.
    }
    recover_ordinary(.owner = $&allocator)
}
