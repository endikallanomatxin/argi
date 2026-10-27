Resource: Type = ()

implement Init#(Resource, ()) (
    .Result : Type = Resource
    .init   = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)

implement InfalliblyCopyable#(Resource) (
    .copy = (.self: &Resource) -> (.value: Resource) {
        value = Resource()
    }
)

consume := (.res: Resource) -> (.status_code: Int32) {
    status_code = 0
}

Wrapper := (
    .res : Resource
)

main := () -> (.status_code: Int32) {
    first := Resource()
    second := copy(.self = &first)
    wrapped: Wrapper = (.res = copy(.self = &first))
    status_code = consume(.res = ~second)
}
