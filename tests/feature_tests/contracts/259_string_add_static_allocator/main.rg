join := #(.Provider: Type: Allocator) (
    .left         : &StringView,
    .right        : &StringView,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(ErrorTracer)
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    assume allocator
    result = ~[left + right]
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&storage
    left ::= "hello"
    right ::= " world"
    first ::= unwrap_or_abort(.value = &left + &right)
    second ::= unwrap_or_abort(.value = join(&left, &right, .allocator = $&storage))
    first_view ::= view(&first)
    second_view ::= view(&second)
    if first_view != "hello world" or second_view != "hello world" { status_code = 1 }
}
