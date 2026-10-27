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

Wrapper := (
    .res : Resource
)

main := () -> (.status_code: Int32) {
    handle := Resource()
    wrapped: Wrapper = (.res = handle)
    _ = wrapped
    status_code = 0
}
