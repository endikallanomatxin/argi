Owner := (.first: DynamicArray#(UIntNative), .second: DynamicArray#(UIntNative))

make_owner := #(.Provider: Type: Allocator) (
    .allocator: $&Provider, .error_tracer: $&Virtual#(ErrorTracer)
) -> (.result: Errable#(Owner, (..out_of_memory))) {
    assume error_tracer

    first ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    second ::= DynamicArray#(UIntNative)(.allocator = allocator)!
    result = ..ok(.first = ~first, .second = ~second)
}

consume := (.owner: Owner) -> () {}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    assume allocator ::= $&GeneralPurposeAllocator(system.page_allocator)
    owner ::= unwrap_or_abort(.value = make_owner()).result
    unwrap_or_abort(.value = push($&owner.second, .value = 1))
    consume(.owner = ~owner)
    status_code = 0
}
