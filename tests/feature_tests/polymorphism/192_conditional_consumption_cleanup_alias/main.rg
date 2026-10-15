Resource: Type = (.value: Int32)

Bundle: Type = (.first: Resource, .second: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

release_if(.resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(resource)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

release_again(.resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    saved ::= release_if(resource, consume)
    result = saved
}

main() -> (.status_code: Int32 = 0) := {
    if true {
        bundle ::= Bundle(Resource(42), Resource(43))
        alias ::= $&bundle.first
        release_again(alias, true)
        if bundle.second.value != 43 { status_code = 3 }
    }
    if drops != 2 { status_code = 1 }

    if true {
        bundle ::= Bundle(Resource(42), Resource(43))
        alias ::= $&bundle.first
        release_again(alias, false)
    }
    if drops != 4 { status_code = 2 }
}
