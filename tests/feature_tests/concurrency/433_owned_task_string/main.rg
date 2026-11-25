forward_value := #(.T: Type) (.value: T) -> (.result: T) { result = ~value }

forward := (.text: String) -> (.result: String) {
    result = forward_value#(String)(.value = ~text)
}

Measure#(.R: Type): Contract = (
    .measure: (.receiver: R) -> (.length: UIntNative) where { reads(receiver) isolated() }
)

implement Measure#($&String) (
    .measure = (.receiver: $&String) -> (.length: UIntNative) {
        length = byte_length(.self = receiver)
    }
)

measure_lent := (.text: Virtual#(Measure)) -> (.length: UIntNative) {
    length = text.measure().length
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    {
        allocated ::= unwrap_or_abort(string_with_length(.allocator = Virtual#(Allocator)($&allocator), .length = 3))
        local ::= forward_value#(String)(.value = ~allocated)
        if byte_length(.self = &local) != 3 { abort }
        borrowed ::= Virtual#(Measure)($&local)
        measurement ::= unwrap_or_abort(async#(measure_lent)(.args = (.text = borrowed), .executor = executor))
        if unwrap_or_abort(await($&measurement)) != 3 { abort }
        _ = unwrap_or_abort(set_ascii(.self = $&local, .index = 0, .byte = 65))
        if unwrap_or_abort(bytes_get(.view = &local, .index = 0)) != 65 { abort }
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
                fresh_view ::= view(.self = &twice_returned)
                if unwrap_or_abort(bytes_get(.view = &fresh_view, .index = 2)) != 66 { abort }
            }
            ..error _ { abort }
        }
    }
    {
        unreturned ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
        discarded_task ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~unreturned), .executor = executor, .ffi = system.ffi))
        -- Dropping the future joins and destroys the unclaimed String.
    }
    {
        empty ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 0))
        task ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~empty), .executor = executor, .ffi = system.ffi))
        returned ::= unwrap_or_abort(await($&task))
        empty_view ::= view(.self = &returned)
        if byte_length(.self = &empty_view) != 0 { abort }
        match bytes_get(.view = &empty_view, .index = 0) {
            ..ok _ { abort }
            ..error failure {
                if is(.value = failure.reason, .variant = ..out_of_bounds) == false { abort }
            }
        }
    }
    recover_ordinary(.owner = $&allocator)
}
