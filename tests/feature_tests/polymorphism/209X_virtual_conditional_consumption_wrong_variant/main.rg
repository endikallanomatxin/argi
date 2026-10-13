Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource, .consume: Bool) -> (.result: ?Int32) where {
        on result ..some { consumes(resource) }
        on result ..none {}
    }
)

Resource: Type = (.value: Int32)

Manager: Type = (.unused: Int32)

Manager implements Releaser

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

release(.self: &Manager, .resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(resource)
        result = ..none
        return
    }

    result = ..some(.value = 42)
}

main() -> () := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)
}
