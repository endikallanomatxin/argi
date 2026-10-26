Resource := (.id: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {}
)

main := () -> (.status_code: Int32 = 0) {
    owner :: Resource = Resource(.id = 1)
    alias := $&owner
    stale := &owner.id
    alias&= Resource(.id = 2)
    status_code = stale&
}
