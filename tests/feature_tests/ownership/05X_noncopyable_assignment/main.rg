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
    first := Resource()
    second := first
    _ = second
    status_code = 0
}
