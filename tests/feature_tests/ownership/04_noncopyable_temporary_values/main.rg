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

Wrapper := (
    .res : Resource
)

consume := (.res: Resource) -> (.status_code: Int32) {
    status_code = 0
}

main := () -> (.status_code: Int32) {
    local_resource := Resource()

    wrapped: Wrapper = (.res = Resource())

    status_code = consume(.res = Resource())
}
