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
}
