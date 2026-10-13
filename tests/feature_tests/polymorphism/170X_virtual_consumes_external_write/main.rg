Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> () where consumes(resource)
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

Resource: Type = (.external: $&Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        self&.external&= 42
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
        value :: Int32 = 41
        resource ::= Resource($&value)
        release_owned(&releaser, $&resource)
    }
    if drops != 1 { status_code = 1 }
}
