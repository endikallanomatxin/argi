Resource := (.value: Int32)

Bundle := (.source: Resource, .destination: Resource, .other: Resource)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {
        drops = drops + 1
    }
)

drops :: Int32 = 0

transfer_if := (.source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

main := () -> (.status_code: Int32 = 0) {
    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        transfer_if($&source, $&destination, false)
    }
    if drops != 2 { status_code = 1 }

    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        transfer_if($&source, $&destination, true)
    }
    if drops != 4 { status_code = 2 }

    if true {
        bundle ::= Bundle(Resource(42), Resource(0), Resource(43))
        deinit($&bundle.destination)
        transfer_if($&bundle.source, $&bundle.destination, true)
        if bundle.other.value != 43 { status_code = 4 }
    }
    if drops != 7 { status_code = 3 }

    if true {
        bundle ::= Bundle(Resource(42), Resource(0), Resource(43))
        deinit($&bundle.destination)
        transfer_if($&bundle.source, $&bundle.destination, false)
    }
    if drops != 10 { status_code = 5 }
}
