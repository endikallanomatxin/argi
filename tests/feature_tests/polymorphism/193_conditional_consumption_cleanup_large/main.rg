Resource: Type = (.value: Int32)

Large: Type = (.values: [128]Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

release_if(.resource: $&Resource, .consume: Bool) -> (.result: ?Large) := {
    if consume {
        deinit(resource)
        result = ..some(.value = Large(zeroed#([128]Int32)()))
        return
    }

    result = ..none
}

main() -> (.status_code: Int32 = 0) := {
    if true {
        resource ::= Resource(42)
        result ::= release_if($&resource, true)
        match result {
            ..some value { if value.value.values[127] != 0 { status_code = 3 } }
            ..none { status_code = 4 }
        }
    }
    if drops != 1 { status_code = 1 }

    if true {
        resource ::= Resource(43)
        release_if($&resource, false)
    }
    if drops != 2 { status_code = 2 }
}
