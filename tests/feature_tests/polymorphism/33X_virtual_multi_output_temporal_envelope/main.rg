ReadablePair : Abstract = (
    get_pair(.self: &Self) -> (.first: &Int32, .second: &Int32)
)

Resource : Type = (
    .first: Int32
    .second: Int32
)

Resource implements ReadablePair

get_pair(.self: &Resource) -> (.first: &Int32, .second: &Int32) := {
    first = &self&.first
    second = &self&.second
}

deinit(.self: $&Resource) -> () #invalidates(self) := {}
read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.first = 1, .second = 2)
    erased ::= to_virtual#(.abstract: ReadablePair)(.value = $&resource)
    pair ::= get_pair(.self = &erased)
    pointer ::= pair.second

    deinit(.self = $&resource)
    read(.value = pointer)
    status_code = 0
}
