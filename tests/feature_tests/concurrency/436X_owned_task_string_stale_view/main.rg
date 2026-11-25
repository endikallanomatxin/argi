edit := (.text: String) -> (.result: String) {
    owned :: String = ~text
    _ = unwrap_or_abort(set_ascii(.self = $&owned, .index = 0, .byte = 65))
    result = ~owned
}

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    text ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    old_view ::= view(.self = &text)
    task ::= unwrap_or_abort(async_owned#(edit)(.args = (.text = ~text), .executor = executor, .ffi = system.ffi))
    returned ::= unwrap_or_abort(await($&task))
    if unwrap_or_abort(bytes_get(.view = &returned, .index = 0)) != 65 { abort }
    _ = unwrap_or_abort(bytes_get(.view = &old_view, .index = 0))
}
