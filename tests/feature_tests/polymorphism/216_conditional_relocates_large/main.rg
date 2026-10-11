Resource: Type = (.value: Int32)

Large: Type = (.values: [128]Int32)

Resource deinit(.self: $&Resource) -> () := { drops = drops + 1 }

drops :: Int32 = 0

transfer_if(
        .source      : $&Resource,
        .destination : $&Resource,
        .move        : Bool
    ) -> (
        .count  : Int32  = 1,
        .result : ?Large
    ) := {
    if move {
        relocate(source, destination)
        result = ..some(.value = Large(zeroed#([128]Int32)()))
        return
    }

    result = ..none
}

main() -> (.status_code: Int32 = 0) := {
    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        transfer_if($&source, $&destination, true)
    }
    if drops != 2 { status_code = 1 }

    if true {
        source ::= Resource(42)
        destination ::= Resource(0)
        deinit($&destination)
        transfer_if($&source, $&destination, false)
    }
    if drops != 4 { status_code = 2 }

    if true {
        source ::= Resource(43)
        destination ::= Resource(0)
        deinit($&destination)
        result ::= transfer_if($&source, $&destination, true)

        match result.result {
            ..some _ { if destination.value != 43 { status_code = 3 } }
            ..none { if source.value != 43 { status_code = 4 } }
        }
    }
    if drops != 6 { status_code = 5 }

    if true {
        source ::= Resource(44)
        destination ::= Resource(0)
        deinit($&destination)
        result ::= transfer_if($&source, $&destination, false)

        match result.result {
            ..some _ { if destination.value != 44 { status_code = 6 } }
            ..none { if source.value != 44 { status_code = 7 } }
        }
    }
    if drops != 8 { status_code = 8 }
}
