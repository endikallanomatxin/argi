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

forward := (.source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) {
    result = transfer_if(source, destination, move)
}

main := () -> (.status_code: Int32 = 0) {
    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        previous ::= &source
        result ::= forward($&source, $&destination, false)

        match result {
            ..some _ { if destination.value != 42 { status_code = 1 } }
            ..none { if source.value != 42 or previous&.value != 42 { status_code = 2 } }
        }
    }
    if drops != 2 { status_code = 3 }

    if true {
        source ::= Resource(43)
        destination ::= Resource(0)
        deinit($&destination)
        result ::= forward($&source, $&destination, true)

        match result {
            ..some _ {
                if destination.value != 43 { status_code = 4 }
                second_result ::= forward($&destination, $&source, false)

                match second_result {
                    ..some _ { if source.value != 43 { status_code = 11 } }
                    ..none { if destination.value != 43 { status_code = 12 } }
                }
            }
            ..none { if source.value != 43 { status_code = 5 } }
        }
    }
    if drops != 4 { status_code = 6 }

    if true {
        bundle ::= Bundle(Resource(44), Resource(0), Resource(45))
        deinit($&bundle.destination)
        source_alias ::= $&bundle.source
        destination_alias ::= $&bundle.destination
        result ::= forward(source_alias, destination_alias, true)

        match result {
            ..some _ { if bundle.destination.value != 44 { status_code = 7 } }
            ..none { if bundle.source.value != 44 { status_code = 8 } }
        }
        if bundle.other.value != 45 { status_code = 9 }
    }
    if drops != 7 { status_code = 10 }
}
