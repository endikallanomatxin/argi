Resource : Type = ()

implement Init#(Resource, ()) (
    .Result: Type = Resource
    .init = (.args: ()) -> (.result: Result) {
        result = ()
    }
)

implement Deinit#(Resource) (
    .deinit = (.self: $&Resource) -> () {

    }
)


copy(.self: &Resource, .tag: Int32 = 1) -> (.value: Resource) := {
    value = Resource()
}

copy(.self: &Resource, .flag: Bool = true) -> (.value: Resource) := {
    value = Resource()
}

Wrapper : Type = (
    .res: Resource
)

main() -> (.status_code: Int32) := {
    handle := Resource()
    wrapped : Wrapper = (.res = handle)
    _ = wrapped
    status_code = 0
}
