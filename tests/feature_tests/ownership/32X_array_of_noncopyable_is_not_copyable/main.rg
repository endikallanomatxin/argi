Resource : Type = ()

implement Init#(Resource, ()) (
    .Result: Type = Resource
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

Resource deinit(.res: $&Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resources :: [2]Resource = (Resource(), Resource())
    copied := resources
    status_code = 0
}
