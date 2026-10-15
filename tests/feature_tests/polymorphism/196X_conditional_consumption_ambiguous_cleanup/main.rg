Resource: Type = (.value: Int32)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

release_if(.resource: $&Resource, .consume: Bool) -> (.result: ?Int32) := {
    if consume { deinit(resource) }

    result = ..some(.value = 42)
}

main() -> () := {
    resource ::= Resource(42)
    release_if($&resource, true)
}
