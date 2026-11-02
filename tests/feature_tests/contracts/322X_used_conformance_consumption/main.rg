Releaser#(.Participant: Type): Contract = (
    .release : (.self: &Participant, .resource: $&Resource) -> () where consumes(resource)
)

Manager := (.unused: Int32)

Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

implement Releaser#(Manager) (
    .release = (.self: &Manager, .resource: $&Resource) -> () {}
)

main := () -> () {
    manager ::= Manager(0)
    resource ::= Resource(0)
    Releaser#(Manager).release(&manager, $&resource)
}
