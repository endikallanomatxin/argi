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

identity := (.res: Resource) -> (.out: Resource) {
    out = res
}

main := () -> (.status_code: Int32) {
    status_code = 0
    _ ::= identity(.res = Resource())
}
