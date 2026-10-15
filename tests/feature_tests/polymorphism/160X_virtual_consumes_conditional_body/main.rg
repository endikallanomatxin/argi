Releaser#(.Participant: Type): Contract = (
    .release: (.self: &Participant, .resource: $&Resource) -> () where consumes(resource)
)

Manager: Type = (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_release_Manager := (.self: &Manager, .resource: $&Resource) -> ()  {
    if self&.unused == 1 { deinit(resource) }
}

release_owned(.releaser: &Virtual#(Releaser), .resource: $&Resource) -> () := {
    release(releaser, resource)
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        release_owned(&releaser, $&resource)
    }
    if drops != 1 { status_code = 1 }
}
