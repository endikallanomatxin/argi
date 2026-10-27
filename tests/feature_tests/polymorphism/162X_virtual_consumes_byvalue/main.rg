Releaser#(.Participant: Type): Contract = (
    .release : (.self: &Participant, .resource: Resource) -> () where consumes(resource)
)

Manager := (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_release_Manager := (.self: &Manager, .resource: Resource) -> () {}

main := () -> () {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)
}
