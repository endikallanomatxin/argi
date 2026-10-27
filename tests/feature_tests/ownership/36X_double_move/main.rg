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

consume := (.res: Resource) -> (.status_code: Int32) {
    status_code = 0
}

main := () -> (.status_code: Int32) {
    handle ::= Resource()
    status_code = consume(.res = ~handle)
    status_code = consume(.res = ~handle)
}
