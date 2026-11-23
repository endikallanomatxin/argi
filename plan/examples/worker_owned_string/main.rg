make_text := (.allocator: Virtual#(Allocator)) -> (.result: String) {
    text ::= unwrap_or_abort(String(.length = 1, .allocator = allocator))
    _ = unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
    result = ~text
}

receive_text := (.future: Future#(String)) -> (.result: String) {
    pending ::= ~future
    result = unwrap_or_abort(await($&pending))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator ::= Virtual#(Allocator)($&storage)
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    -- Establish the constructor, virtual provider and cleanup as a control.
    {
        control ::= make_text(allocator)
        if unwrap_or_abort(bytes_get(.view = &control, .index = 0)) != 65 { abort }
    }
    if has_live_allocations(&storage) { abort }
    submission ::= async#(make_text)(.args = (.allocator = allocator))
    match submission {
        ..ok ~future {
            text ::= receive_text(~future)
            if has_live_allocations(&storage) == false { abort }
            if unwrap_or_abort(bytes_get(.view = &text, .index = 0)) != 65 { abort }
        }
        ..error failure { match failure.reason {
            ..unsupported_task_value { status_code = 2 }
            ..task_start_failed { status_code = 3 }
            ..executor_mismatch { status_code = 4 }
        } return }
    }
    if has_live_allocations(&storage) { abort }
    {
        abandoned ::= unwrap_or_abort(async#(make_text)(.args = (.allocator = allocator)))
    }
    if has_live_allocations(&storage) { abort }
}
