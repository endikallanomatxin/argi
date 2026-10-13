Reply: Type = (..success ?Int32, ..failure)

Releaser: Abstract = (
    release(.self: &Self, .resource: $&Resource, .consume: Bool) -> (.result: Reply) where {
        on result ..success {
            consumes(resource)
            on result ..some {}
            on result ..none {}
        }
        on result ..failure {}
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

release(.self: &Manager, .resource: $&Resource, .consume: Bool) -> (.result: Reply) := {
    if consume {
        deinit(resource)
        result = ..success ..some(.value = 42)
        return
    }

    result = ..failure
}

main() -> (.status_code: Int32 = 0) := {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        result ::= release(&releaser, $&resource, false)

        match result {
            ..failure { if resource.value != 42 { status_code = 1 } }
            ..success ~_ { status_code = 2 }
        }
    }
    if drops != 1 { status_code = 3 }

    if true {
        resource ::= Resource(43)
        release(&releaser, $&resource, true)
    }
    if drops != 2 { status_code = 4 }
}
