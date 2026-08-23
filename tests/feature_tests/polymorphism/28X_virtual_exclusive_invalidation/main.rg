Resettable : Abstract = (
    reset(.self: $$&Self) -> ()
)

Resource : Type = (
    .value: Int32
)

Resource implements Resettable

reset(.self: $$&Resource) -> () #invalidates(self) := {
    self&.value = 0
}

read(.value: &Resource) -> () := {}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 42)
    pointer ::= &resource
    erased ::= to_virtual#(.abstract: Resettable)(.value = $&resource)
    reset(.self = $$&erased)
    read(.value = pointer)
    status_code = 0
}
