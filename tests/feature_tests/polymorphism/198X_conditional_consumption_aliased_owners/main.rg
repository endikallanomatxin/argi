Resource: Type = (.value: Int32)

Resource deinit(.self: $&Resource) -> () := {}

release_if(.first: $&Resource, .second: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume {
        deinit(first)
        deinit(second)
        result = ..some(.value = 42)
        return
    }

    result = ..none
}

main() -> () := {
    resource ::= Resource(42)
    alias ::= $&resource
    release_if($&resource, alias, true)
}
