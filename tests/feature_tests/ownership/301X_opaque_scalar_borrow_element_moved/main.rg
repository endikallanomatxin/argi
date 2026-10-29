Borrowing := (.counter: $&Int32)

implement Deinit#(Borrowing) (
    .deinit = (.self: $&Borrowing) -> () {
        self&.counter&= self&.counter&+ 1
    }
)

exercise := #(.AllocatorType: Type: Allocator#(AllocatorType)) (
    .counter: $&Int32, .allocator: $&AllocatorType, .error_tracer: $&Virtual#(ErrorTracer)
) -> () {
    assume error_tracer
    assume allocator
    array ::= unwrap_or_abort(.value = DynamicArray#(.t: Borrowing)(.capacity = 1))
    element ::= Borrowing(.counter = counter)
    pushed ::= push(.self = $&array, .value = ~element)
    if is(.value = pushed, .variant = ..error) { abort }
    counter&= element.counter&
}

main := (.system: System) -> (.status_code: Int32) {
    assume error_tracer ::= $&noop_error_tracer
    counter :: Int32 = 0
    exercise(.counter = $&counter, .allocator = system.page_allocator)
    status_code = 0
}
