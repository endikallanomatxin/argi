choose := (.yes: Bool, .first: String, .second: String) -> (.result: String) {
    if yes { result = ~first } else { result = ~second }
}
return_owner := (.text: String) -> (.result: String) { result = ~text }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    local ::= unwrap_or_abort(string_with_length(.allocator = Virtual#(Allocator)($&allocator), .length = 3))
    concurrent_allocator ::= CAllocator(.ffi = system.ffi)
    shared ::= $$&concurrent_allocator
    text ::= unwrap_or_abort(string_with_shared_c_storage(.allocator = shared, .length = 3))
    selected ::= choose(.yes = byte_length(.self = &text) == 3, .first = ~text, .second = ~local)
    task ::= unwrap_or_abort(async_owned#(return_owner)(.args = (.text = ~selected), .executor = executor, .ffi = system.ffi))
    match await($&task) {
        ..ok ~returned {}
        ..error _ { abort }
    }
    recover_ordinary(.owner = $&concurrent_allocator)
}
