Releaser#(.Participant: Type): Contract = (
    .release : (.self: &Participant, .resource: $&Resource, .consume: Bool) -> (
        .count: Int32, .result: ?Large
    ) where {
        on result ..some { consumes(resource) }
        on result ..none {}
    }
)

Resource := (.value: Int32)

Large := (.values: [128]Int32)

Manager := (.unused: Int32)

implement Releaser#(Manager) (.release = _impl_release_Manager)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

_impl_release_Manager := (.self: &Manager, .resource: $&Resource, .consume: Bool) -> (
    .count: Int32, .result: ?Large
) {
    count = 42
    if consume {
        deinit(resource)
        result = ..some(.value = Large(zeroed#([128]Int32)()))
        return
    }

    result = ..none
}

main := () -> (.status_code: Int32 = 0) {
    manager ::= Manager(0)
    releaser ::= to_virtual#(Releaser)(&manager)

    if true {
        resource ::= Resource(42)
        result ::= release(&releaser, $&resource, false)

        match result.result {
            ..none { if resource.value != 42 { status_code = 1 } }
            ..some _ { status_code = 2 }
        }
        if result.count != 42 { status_code = 3 }
    }
    if drops != 1 { status_code = 4 }

    if true {
        resource ::= Resource(43)
        release(&releaser, $&resource, true)
    }
    if drops != 2 { status_code = 5 }
}
