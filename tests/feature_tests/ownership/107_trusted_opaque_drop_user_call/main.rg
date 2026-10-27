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

main := () -> (.status_code: Int32) {
    value :: Resource = Resource()
    trusted_opaque_drop#(.t: Resource)(.slot = $&value)
    status_code = 0
}
