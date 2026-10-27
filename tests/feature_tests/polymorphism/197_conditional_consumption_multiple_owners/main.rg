Resource := (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

release_if := (.first: $&Resource, .second: $&Resource, .consume: Bool) -> (.result: ?Int32) {
    if consume {
        deinit(first)
        deinit(second)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

main := () -> (.status_code: Int32 = 0) {
    if true {
        first ::= Resource(42)
        second ::= Resource(43)
        release_if($&first, $&second, true)
    }
    if drops != 2 { status_code = 1 }

    if true {
        first ::= Resource(42)
        second ::= Resource(43)
        release_if($&first, $&second, false)
    }
    if drops != 4 { status_code = 2 }
}
