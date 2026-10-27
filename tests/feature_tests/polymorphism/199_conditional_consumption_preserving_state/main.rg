Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

release_if := (.resource: $&Resource, .consume: Bool) -> (.result: ?Int32) {
    if consume {
        deinit(resource)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

main := () -> (.status_code: Int32 = 0) {
    if true {
        resource ::= Resource(42)
        previous ::= &resource.value
        result ::= release_if($&resource, false)

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
        result ::= release_if($&resource, true)

        match result {
            ..none { status_code = 5 }
            ..some _ {
                resource = Resource(44)
                if resource.value != 44 { status_code = 6 }
            }
        }
    }
    if drops != 3 { status_code = 7 }
}
