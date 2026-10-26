drops :: Int32 = 0

record_drop := () -> () { drops = drops + 1 }

Policy := (.id: Int32)

implement Deinit<Policy> (
    .deinit = (.self: $&Policy) -> () { record_drop() }
)

implement HashPolicy<Policy, Int32> (
    .Query : Type = &Int32
    .query = (.self: &Policy, .key: &Int32) -> (.query: Query) { query = key }

    .hash  = (.self: &Policy, .key: &Int32) -> (.hash: UIntNative) { hash = 0 }
    .equal = (.self: &Policy, .left: &Int32, .right: &Int32) -> (.ok: Bool) {
        ok = left&== right&
    }
)

FailAllocator: Type = ()

implement Allocator<FailAllocator> (
    .allocate = (.self: $&FailAllocator, .size: UIntNative, .alignment: UIntNative) -> (
        .result: Errable<Allocation, (..out_of_memory)>
    ) {
        result = ..error(.reason = ..out_of_memory)
    }
)

failed := (.allocator: $&FailAllocator) -> () {
    policy ::= Policy(1)
    outcome ::= HashMap<.key: Int32, .value: Int32, .policy: Policy>(
        .policy = ~policy, .allocator = allocator
    )
    match outcome { ..ok ~map { abort } ..error _ {} }
    if drops != 1 { abort }
}

successful := (.allocator: $&PageAllocator) -> () {
    policy ::= Policy(2)
    map ::= unwrap_or_abort(
        HashMap<.key: Int32, .value: Int32, .policy: Policy>(
            .policy = ~policy, .allocator = allocator
        )
    )
    if drops != 1 { abort }
    Deinit<HashMap<.key: Int32, .value: Int32, .policy: Policy>>.deinit($&map)
    if drops != 2 { abort }
}

main := (.system: System) -> (.status_code: Int32 = 0) {
    failing ::= FailAllocator()
    failed($&failing)
    if drops != 1 { abort }
    successful(system.page_allocator)
    if drops != 2 { abort }
}
