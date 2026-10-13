Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

transfer_if(.source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) := {
    if move { relocate(source, destination) }
    result = ..some(.value = 1)
}

main() -> () := {
    source ::= Resource(42)
    destination ::= Resource(0)
    deinit($&destination)
    transfer_if($&source, $&destination, true)
}
