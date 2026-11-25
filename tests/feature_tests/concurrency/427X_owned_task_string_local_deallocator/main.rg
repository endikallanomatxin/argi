forward := (.text: String) -> (.result: String) { result = ~text }

return_owner := (.text: String) -> (.result: String) { result = ~text }
main := (.system: System) -> () {
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    executor ::= Virtual#(Executor)($&provider)
    allocator ::= CAllocator(.ffi = system.ffi)
    text ::= unwrap_or_abort(string_with_length(.allocator = Virtual#(Allocator)($&allocator), .length = 3))
    forwarded ::= forward(.text = ~text)
    task ::= unwrap_or_abort(async_owned#(return_owner)(.args = (.text = ~forwarded), .executor = executor, .ffi = system.ffi))
    match await($&task) {
        ..ok ~returned {}
        ..error _ { abort }
    }
}
