Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

copy(.self: &Resource) -> (.value: Resource) := {
    value = Resource()
}

Resource implements InfalliblyCopyable

consume(.res: Resource) -> (.status_code: Int32) := {
    status_code = 0
}

Wrapper : Type = (
    .res: Resource
)

main() -> (.status_code: Int32) := {
    first := Resource()
    second := copy(.self = &first)
    wrapped : Wrapper = (.res = copy(.self = &first))
    status_code = consume(.res = ~second)
}
