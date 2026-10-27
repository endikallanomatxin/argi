Resource: Type = ()

implement Init#(Resource) (
    .init = () -> (.result: Resource) {
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

Wrapper := (
    .res : Resource
)

main := () -> (.status_code: Int32) {
    handle := Resource()
    wrapped: Wrapper = (.res = handle)
    _ = wrapped
    status_code = 0
}
