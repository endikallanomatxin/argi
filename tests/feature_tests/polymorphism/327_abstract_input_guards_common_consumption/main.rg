Selection: Type = (..left, ..right)

Resource: Type = (.value: Int32)

drops :: Int32 = 0

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource, .mode: Selection) -> (.value: Int32) where {
        consumes(resource)
        on mode ..left {}
        on mode ..right {}
    }
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

release(.self: &Manager, .resource: $&Resource, .mode: Selection) -> (.value: Int32) := {
    deinit(resource)
    value = 42
}

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    {
        resource ::= Resource(7)
        value ::= release(&releaser, $&resource, ..left)
        if value != 42 { abort }
    }

    if drops != 1 { abort }
}
