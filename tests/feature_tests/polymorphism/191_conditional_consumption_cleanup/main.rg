Resource: Type = (.value: Int32)

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

main() -> (.status_code: Int32 = 0) := {
    if true {
        resource ::= Resource(42)
        release_if($&resource, true)
    }
    if drops != 1 { status_code = 1 }

    if true {
        resource ::= Resource(43)
        release_if($&resource, false)
    }
    if drops != 2 { status_code = 2 }
}
