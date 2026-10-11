Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

transfer_pair_if(
        .first              : $&Resource,
        .first_destination  : $&Resource,
        .second             : $&Resource,
        .second_destination : $&Resource,
        .move               : Bool
    ) -> (
        .result : ?Int32
    ) := {
    if move {
        relocate(first, first_destination)
        relocate(second, second_destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

main() -> () := {
    source ::= Resource(42)
    first_destination ::= Resource(0)
    second_destination ::= Resource(0)
    deinit($&first_destination)
    deinit($&second_destination)
    transfer_pair_if($&source, $&first_destination, $&source, $&second_destination, true)
}
