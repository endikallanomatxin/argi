Resource := (.value: Int32)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {

    }
)

release_if := (.resource: $&Resource, .consume: Bool) -> () {
    if consume { deinit(resource) }
}

main := () -> () {
    resource ::= Resource(42)
    release_if($&resource, true)
}
