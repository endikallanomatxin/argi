Readable : Abstract = (
    get_value(.self: &Self) -> (.value: &Int32)
)

Resource : Type = (
    .value: Int32
)

Resource implements Readable

get_value(.self: &Resource) -> (.value: &Int32) := {
    value = &self&.value
}

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 42)
    erased ::= to_virtual#(.abstract: Readable)(.value = $&resource)
    pointer ::= get_value(.self = &erased)
    deinit(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
