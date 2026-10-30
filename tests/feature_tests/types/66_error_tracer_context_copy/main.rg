..copy_test_failure

fail := (.error_tracer: $&Virtual#(ErrorTracer)) -> !!Void {
    assume error_tracer
    result = ..error(.reason = ..copy_test_failure)
}

context_failure := (.allocator: $&PageAllocator, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Errable#(
        .t          : Void,
        .reasons    : (..copy_test_failure),
        .error_type : ErrorWithTrace#((..copy_test_failure))
    )
) {
    assume error_tracer

    text ::= unwrap_or_abort(.value = String(.allocator = allocator, .length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 1, .byte = 66))
    _ ::= unwrap_or_abort(.value = set_ascii(.self = $&text, .index = 2, .byte = 90))
    all ::= view(.self = &text)
    view ::= unwrap_or_abort(.value = slice(.self = all, .start = 0, .count = 2))
    fail()!! view
    result = ..ok Void()
}

main := (.system: System) -> (.status_code: Int32) {
    tracer ::= FixedSizeErrorTracer(.buffer = view($&zeroed#(.t: [4096]UInt8)()))
    virtual_tracer ::= to_virtual#(.contract: ErrorTracer)(.value = $&tracer)
    assume error_tracer ::= $&virtual_tracer
    failed ::= context_failure(.allocator = system.page_allocator)
    match failed {
        ..ok _ { status_code = 1 }
        ..error&err {
            reported ::= report_trace(
                .tracer = err&.tracer, .writer = $&system.terminal&.stderr
            )
            match reported { ..ok _ { status_code = 0 } ..error _ { status_code = 2 } }
        }
    }
}
