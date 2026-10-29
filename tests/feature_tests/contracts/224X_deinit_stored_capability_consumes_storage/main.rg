Counter := (.allocation: Allocation)

Owner := (.value: Int32, .counter: $&Counter)

release_storage := (.counter: $&Counter) -> () {
    deinit(.self = $&counter&.allocation)
}

observe := (.self: $&Owner) -> () { release_storage(.counter = self&.counter) }

implement Deinit#(Owner) (.deinit = observe)

create := (.counter: $&Counter) -> () {
    assume counter
    value ::= Owner(.value = 3, .counter = counter)
}

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    counter ::= Counter(.allocation = ~unwrap_or_abort(allocate_bytes(allocator, .size = 1)))
    create($&counter)
}
