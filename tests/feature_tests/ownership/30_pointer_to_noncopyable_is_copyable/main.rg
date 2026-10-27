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

consume_ptr := (.ptr: &Resource) -> (.status_code: Int32) {
    status_code = 0
}

main := () -> (.status_code: Int32) {
    resource := Resource()
    first_ptr: &Resource = &resource
    second_ptr: &Resource = first_ptr

    status_code = consume_ptr(.ptr = second_ptr).status_code
}
