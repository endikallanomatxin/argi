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

_ordinary_copy_0 := (.self: &Resource, .tag: Int32 = 1) -> (.value: Resource) {
    value = Resource()
}

_ordinary_copy_1 := (.self: &Resource, .flag: Bool = true) -> (.value: Resource) {
    value = Resource()
}

duplicate := (.source: Resource) -> (.value: Resource) {
    return source
}

main := () -> (.status_code: Int32) {
    status_code = 0
    _ ::= duplicate(.source = Resource())
}
