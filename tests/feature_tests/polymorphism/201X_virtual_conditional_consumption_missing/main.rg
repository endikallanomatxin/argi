Releaser<.Participant: Type>: Contract = (
    .release : (.self: &Participant, .resource: $&Resource) -> (.result: ?Int32) where {
        on result ..some { consumes(resource) }
        on result ..none {}
    }
)

Resource := (.value: Int32)

Manager := (.unused: Int32)

implement Releaser<Manager> (.release = _impl_release_Manager)

implement Deinit<Resource> (
    .deinit = (.self: $&Resource) -> () {

    }
)

_impl_release_Manager := (.self: &Manager, .resource: $&Resource) -> (.result: ?Int32) {
    result = ..some(.value = 42)
}

main := () -> () {
    manager ::= Manager(0)
    releaser ::= to_virtual<Releaser>(&manager)
}
