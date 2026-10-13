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
        drops = drops + 1
    }
)

drops :: Int32 = 0

release(.self: &Manager, .resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(resource)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

release_again(
        .releaser : &Virtual#(Releaser),
        .resource : $&Resource,
        .consume  : Bool
    ) -> (
        .result : ?Int32
    ) := {
    saved ::= release(releaser, resource, consume)
    result = saved
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        previous ::= &resource.value
        result ::= release_again(&releaser, $&resource, false)

        match result {
            ..none {
                if resource.value != 42 { status_code = 1 }
                if previous&!= 42 { status_code = 2 }
            }
            ..some _ { status_code = 3 }
        }
    }
    if drops != 1 { status_code = 4 }

    if true {
        resource ::= Resource(43)
        release_again(&releaser, $&resource, true)
    }
    if drops != 2 { status_code = 5 }
}
