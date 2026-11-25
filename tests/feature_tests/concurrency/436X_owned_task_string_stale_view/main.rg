forward := (.text: String) -> (.result: String) { result = ~text }

main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    text ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    old_view ::= view(.self = &text)
    task ::= unwrap_or_abort(async_owned#(forward)(.args = (.text = ~text), .executor = executor, .ffi = system.ffi))
    returned ::= unwrap_or_abort(await($&task))
    if unwrap_or_abort(bytes_get(.view = &returned, .index = 0)) != 0 { abort }
    _ = unwrap_or_abort(bytes_get(.view = &old_view, .index = 0))
}
