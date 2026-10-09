Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

transfer_if(.source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) := {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

main() -> (.status_code: Int32 = 0) := {
    source ::= Resource(42)
    destination ::= Resource(0)
    deinit($&destination)
    previous ::= &source
    transfer_if($&source, $&destination, true)
    status_code = previous&.value
}
