Resource: Type = ()

implement Init<Resource, ()> (
    .Result : Type = Resource
    .init   = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

implement Deinit<Resource> (
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
