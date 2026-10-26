Owner := (.value: Int32)

implement Deinit<Owner> (
    .deinit = (.self: $&Owner) -> () {}
)

Policy: Type = ()

implement OrderPolicy<Policy, Owner> (
    .less = (.self: &Policy, .left: &Owner, .right: &Owner) -> (.ok: Bool) {
        ok = left&.value < right&.value
    }
)

main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    policy ::= Policy()
    queue ::= PriorityQueue<.t: Owner>(.order = &policy)!!!
    push($&queue, .value = Owner(.value = 1))!!!
    copied ::= peek(&queue).value
    status_code = 0
}
