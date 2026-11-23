consume_text := (.text: String) -> (.byte: UInt8) {
    owner ::= ~text
    byte = unwrap_or_abort(bytes_get(.view = &owner, .index = 0))
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocator ::= Virtual#(Allocator)($&storage)
    provider ::= ThreadedExecutor(.ffi = system.ffi)
    assume executor ::= Virtual#(Executor)($&provider)
    text ::= unwrap_or_abort(String(.length = 1, .allocator = allocator))
    _ = unwrap_or_abort(set_ascii(.self = $&text, .index = 0, .byte = 65))
    submission ::= async#(consume_text)(.args = (.text = ~text))
    match submission {
        ..ok ~future {
            byte ::= unwrap_or_abort(await($&future))
            if byte != 65 { abort }
        }
        ..error failure { match failure.reason {
            ..unsupported_task_value { status_code = 2 }
            ..task_start_failed { status_code = 3 }
            ..executor_mismatch { status_code = 4 }
        } }
    }
}
