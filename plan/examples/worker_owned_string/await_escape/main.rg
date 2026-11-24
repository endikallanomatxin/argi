-- Compile-only lifetime case: the result crosses the lifetime of its allocator.
make_text := (.allocator: Virtual#(Allocator)) -> (.result: String) {
    text ::= unwrap_or_abort(String(.length = 1, .allocator = allocator))
    _ = unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
    result = ~text
}

receive_text := (.future: Future#(String)) -> (.result: String) {
    pending ::= ~future
    result = unwrap_or_abort(await($&pending))
}

produce := (.system: System, .executor: Virtual#(Executor)) -> (.result: String) {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    provider ::= Virtual#(Allocator)($&storage)
    future ::= unwrap_or_abort(async#(make_text)(.args = (.allocator = provider), .executor = executor))
    result = receive_text(~future)
}
main := (.system: System) -> () {
    executor ::= InlineExecutor(.ffi = system.ffi)

    text ::= produce(system, Virtual#(Executor)($&executor))
}
