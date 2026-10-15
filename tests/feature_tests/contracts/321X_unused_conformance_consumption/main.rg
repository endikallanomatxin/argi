Releaser#(.Participant: Type): Contract = (
    .release: (.self: &Participant, .resource: $&Resource) -> () where consumes(resource)
)

Manager: Type = (.unused: Int32)
Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {}
)

implement Releaser#(Manager) (
    .release = (.self: &Manager, .resource: $&Resource) -> () {}
)

main := () -> () {}
