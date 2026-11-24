consume := (.text: String) -> (.length: UIntNative) {
    owned :: String = ~text
    _ = unwrap_or_abort(set_ascii(.self = $&owned, .index = 2, .byte = 65))
    length = byte_length(.self = &owned)
    if unwrap_or_abort(bytes_get(.view = &owned, .index = 2)) != 65 { abort }
}
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&allocator
    text ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    task ::= unwrap_or_abort(async_owned#(consume)(.args = (.text = ~text), .executor = executor, .ffi = system.ffi))
    if unwrap_or_abort(await($&task)) != 3 { abort }
    recover_ordinary(.owner = $&allocator)
}
