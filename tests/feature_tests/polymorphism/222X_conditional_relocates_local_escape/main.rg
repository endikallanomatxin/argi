Resource: Type = (.value: &Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

global :: Int32 = 1

transfer_if(.source: $&Resource, .destination: $&Resource, .move: Bool) -> (.result: ?Int32) := {
    if move {
        relocate(source, destination)
        result = ..some(.value = 1)
        return
    }

    result = ..none
}

escape() -> (.resource: Resource) := {
    local :: Int32 = 42
    source ::= Resource(&local)
    destination ::= Resource(&global)
    deinit($&destination)
    result ::= transfer_if($&source, $&destination, true)

    match result {
        ..some _ { resource = ~destination }
        ..none { resource = ~source }
    }
}

main() -> () := {
    resource ::= escape()
}
