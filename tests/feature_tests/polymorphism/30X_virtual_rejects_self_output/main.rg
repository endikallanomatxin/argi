Cloneable : Abstract = (
    clone(.self: &Self) -> (.copy: Self)
)

Thing : Type = (
    .value: Int32
)

Thing implements Cloneable

clone(.self: &Thing) -> (.copy: Thing) := {
    copy = self&
}

main() -> (.status_code: Int32) := {
    thing :: Thing = (.value = 42)
    erased ::= to_virtual#(.abstract: Cloneable)(.value = $&thing)
    copy ::= clone(.self = &erased)
    status_code = copy.value
}
