Counter := (.value: Int32)

Owner := (.value: Int32, .counter: $&Counter)

add_count := (.amount: Int32, .counter: $&Counter) -> () {
    counter&.value = [counter&.value + amount]
}

observe := (.self: $&Owner) -> () {
    add_count(.amount = self&.value, .counter = self&.counter)
}

implement Deinit#(Owner) (.deinit = observe)

create := (
    .counter: $&Counter, .allocator: $&PageAllocator, .error_tracer: $&Virtual#(ErrorTracer)
) -> () {
    assume error_tracer
    assume counter
    assume allocator
    values ::= unwrap_or_abort(DynamicArray#(Owner)(.capacity = 1))
    value ::= Owner(.value = 3, .counter = counter)
    push_assume_capacity#(Owner)($&values, .value = ~value)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    counter ::= Counter(0)
    create($&counter, system.page_allocator)
    if counter.value != 3 { abort }
}
