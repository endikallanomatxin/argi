Resource: Type = ()

ResourceInitArgs: Type = ()

implement Init#(Resource, ResourceInitArgs) (
    .Result : Type = Resource

    .init = ResourceInitArgs -> (.result: Result) {
        result = ()
    }
)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

duplicate := (.source: Resource) -> (.value: Resource) {
    return source
}

main := () -> (.status_code: Int32) {
    status_code = 0
    _ ::= duplicate(.source = Resource())
}
