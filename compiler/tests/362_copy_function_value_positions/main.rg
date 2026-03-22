Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

copy(.res: Resource) -> (.out: Resource) := {
    out = Resource()
}

consume(.res: Resource) -> (.status_code: Int32) := {
    status_code = 0
}

Wrapper : Type = (
    .res: Resource
)

main() -> (.status_code: Int32) := {
    first := Resource()
    second := first
    wrapped : Wrapper = (.res = first)
    status_code = consume(.res = second)
}
