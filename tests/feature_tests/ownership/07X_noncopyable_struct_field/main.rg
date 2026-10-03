Resource : Type = ()

Resource init() -> (.result: Resource) := {
    result = ()
}

Resource deinit(.res: $&Resource) -> () := {}

Wrapper : Type = (
    .res: Resource
)

main() -> (.status_code: Int32) := {
    handle := Resource()
    wrapped : Wrapper = (.res = handle)
    _ = wrapped
    status_code = 0
}
