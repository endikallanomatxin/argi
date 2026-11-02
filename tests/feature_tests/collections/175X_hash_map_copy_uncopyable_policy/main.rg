Policy := (.id: Int32)

implement Deinit#(Policy) (
    .deinit = (.self: $&Policy) -> () {}
)

implement HashPolicy#(Policy, Int32) (
    .Query : Type = &Int32
    .query = (.self: &Policy, .key: &Int32) -> (.query: Query) { query = key }
    .hash = (.self: &Policy, .key: &Int32) -> (.hash: UIntNative) { hash = 7 }
    .equal = (.self: &Policy, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = [left& == right&]
    }
)

main := (.system: System) -> (.status_code: Int32 = 0) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    map ::= HashMap#(.key: Int32, .value: Int32, .policy: Policy)(
        .policy = Policy(.id = 1), .allocator = allocator
    )!!!
    put(.self = $&map, .key = 1, .value = 2, .allocator = allocator)!!!
    copied ::= copy(.self = &map, .allocator = allocator)
}
