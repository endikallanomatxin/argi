Releaser#(.Participant: Type): Contract = (
    .release: (.self: &Participant, .resource: $&Resource) -> () where consumes(resource)
)
Observer#(.Participant: Type): Contract = (
    .observe: (.self: &Participant, .resource: $&Resource) -> ()
)
Manager: Type = (.unused: Int32)
Resource: Type = (.value: Int32)
implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)
ignore := (.self: &Manager, .resource: $&Resource) -> () {}
implement Releaser#(Manager) (.release = ignore)
implement Observer#(Manager) (.observe = ignore)
main := () -> () {
    manager ::= Manager(0)
    resource ::= Resource(0)
    Observer#(Manager).observe(&manager, $&resource)
}
