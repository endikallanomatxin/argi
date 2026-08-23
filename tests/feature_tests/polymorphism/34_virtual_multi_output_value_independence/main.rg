ReadablePair : Abstract = (
    get_pair(.self: &Self) -> (.pointer: &Int32, .number: Int32)
)

Resource : Type = (
    .value: Int32
)

Resource implements ReadablePair

get_pair(.self: &Resource) -> (.pointer: &Int32, .number: Int32) := {
    pointer = &self&.value
    number = self&.value
}

deinit(.self: $$&Resource) -> () #invalidates(self) := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 42)
    erased ::= to_virtual#(.abstract: ReadablePair)(.value = $&resource)
    pair ::= get_pair(.self = &erased)

    deinit(.self = $$&resource)
    status_code = pair.number - 42
}
