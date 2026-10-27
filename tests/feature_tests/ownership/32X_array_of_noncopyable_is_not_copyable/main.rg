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
    resources :: [2]Resource = (Resource(), Resource())
    copied := resources
    status_code = 0
}
