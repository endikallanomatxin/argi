Resource : Type = ()

init(.res: $&Resource) -> () := {}

deinit(.res: $&Resource) -> () := {}

Wrapper : Type = (
    .res: Resource
)

consume(.res: Resource) -> (.status_code: Int32) := {
    status_code = 0
}

main() -> (.status_code: Int32) := {
    local_resource := Resource()

    wrapped : Wrapper = (.res = Resource())

    status_code = consume(.res = Resource())
}
