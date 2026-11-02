Value := (.id: Int32)

implement Deinit#(Value) (
    .deinit = (.self: $&Value) -> () {}
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Value, .policy: StandardHashPolicy)(
        .policy = StandardHashPolicy(), .allocator = allocator
    )!!!
    put(.self = $&map, .key = 1, .value = Value(.id = 2), .allocator = allocator)!!!
    copied ::= copy(.self = &map, .allocator = allocator)
}
