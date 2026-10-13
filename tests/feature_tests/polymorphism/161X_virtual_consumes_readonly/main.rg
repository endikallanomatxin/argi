Releaser: Abstract = (
    release(.self: &Self, .resource: &Resource) -> () where consumes(resource)
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

release(.self: &Manager, .resource: &Resource) -> () := {}

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)
}
