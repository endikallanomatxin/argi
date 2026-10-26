Counter := (.allocation: Allocation)

Owner := (.value: Int32)

release_storage := (.counter: $&Counter = reach counter) -> () {
    deinit(.self = $&counter&.allocation)
}

observe := (.self: $&Owner) -> () { release_storage() }

implement Deinit<Owner> (.deinit = observe)

create := (.counter: $&Counter) -> () {
    assume counter
    value ::= Owner(3)
}

main := (.system: System) -> () {
    assume allocator := system.page_allocator
    counter ::= Counter(.allocation = ~unwrap_or_abort(allocate_bytes(allocator, .size = 1)))
    create($&counter)
}
