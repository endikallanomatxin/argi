Counter := (.value: Int32)

Owner := (.value: Int32)

add_count := (.amount: Int32, .counter: $&Counter = reach counter) -> () {
    counter&.value = [counter&.value + amount]
}

observe := (.self: $&Owner) -> () { add_count(.amount = self&.value) }

implement Deinit<Owner> (.deinit = observe)

create := (.counter: $&Counter, .allocator: $&PageAllocator) -> () {
    assume counter
    assume allocator
    values ::= unwrap_or_abort(DynamicArray<Owner>(.capacity = 1))
    value ::= Owner(3)
    push_assume_capacity<Owner>($&values, .value = ~value)
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    counter ::= Counter(0)
    create($&counter, system.page_allocator)
    if counter.value != 3 { abort }
}
