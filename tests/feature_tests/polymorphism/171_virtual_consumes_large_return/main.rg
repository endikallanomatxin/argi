Large := (.values: [128]Int32)

Releaser#(.Participant: Type): Contract = (
    .release : (.self: &Participant, .resource: $&Resource) -> (.result: Large) where consumes(
        resource
    )
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

_impl_release_Manager := (.self: &Manager, .resource: $&Resource) -> (.result: Large) {
    deinit(resource)
    result = Large(zeroed#([128]Int32)())
}

main := () -> (.status_code: Int32 = 0) {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        large ::= release(&releaser, $&resource)
        if large.values[127] != 0 { status_code = 2 }
    }
    if drops != 1 { status_code = 1 }
}
