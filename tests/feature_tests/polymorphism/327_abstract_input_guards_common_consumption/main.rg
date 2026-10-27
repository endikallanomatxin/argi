Selection: Type = (..left, ..right)

Resource := (.value: Int32)

drops :: Int32 = 0

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

Releaser#(.Participant: Type): Contract = (
    .release : (.self: &Participant, .resource: $&Resource, .mode: Selection) -> (.value: Int32) where {
        consumes(resource)
        on mode ..left {}
        on mode ..right {}
    }
)

Manager := (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

_impl_release_Manager := (.self: &Manager, .resource: $&Resource, .mode: Selection) -> (
    .value : Int32
) {
    deinit(resource)
    value = 42
}

main := () -> () {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    {
        resource ::= Resource(7)
        value ::= release(&releaser, $&resource, ..left)
        if value != 42 { abort }
    }

    if drops != 1 { abort }
}
