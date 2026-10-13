Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> () where consumes(resource)
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

release(.self: &Manager, .resource: $&Resource) -> () := { deinit(resource) }

release_owned(.releaser: &Virtual#(Releaser), .resource: $&Resource) -> () := {
    release(releaser, resource)
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        alias ::= $&resource
        release_owned(&releaser, alias)
    }
    if drops != 1 { status_code = 1 }
}
