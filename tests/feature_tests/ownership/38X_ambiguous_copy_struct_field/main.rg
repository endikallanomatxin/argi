Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

copy(.res: Resource, .tag: Int32 = 1) -> (.out: Resource) := {
    out = Resource()
}

copy(.res: Resource, .flag: Bool = true) -> (.out: Resource) := {
    out = Resource()
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
