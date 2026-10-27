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

main := () -> (.status_code: Int32) {
    value :: Resource = Resource()
    trusted_opaque_drop#(.t: Resource)(.slot = $&value)
    status_code = 0
}
