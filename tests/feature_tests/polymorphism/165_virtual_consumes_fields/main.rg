Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource) -> () where consumes(resource)
)

Manager: Type = (.unused: Int32)

Manager implements Releaser

Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

drops :: Int32 = 0

release(.self: &Manager, .resource: $&Resource) -> () := { deinit(resource) }

release_owned(.releaser: &Virtual#(Releaser), .resource: $&Resource) -> () := {
    release(releaser, resource)
}

Bundle: Type = (.first: Resource, .second: Resource)

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        bundle ::= Bundle(Resource(42), Resource(43))
        previous ::= &bundle.second.value
        release_owned(&releaser, $&bundle.first)
        if previous&!= 43 { status_code = 3 }
        if bundle.second.value != 43 { status_code = 2 }
    }
    if drops != 2 { status_code = 1 }
}
