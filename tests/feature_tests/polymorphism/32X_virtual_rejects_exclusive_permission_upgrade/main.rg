Resettable : Abstract = (
    reset(.self: $$&Self) -> ()
)

Resource : Type = (
    .value: Int32
)

Resource implements Resettable

reset(.self: $$&Resource) -> () := {
    self&.value = 0
}

main() -> (.status_code: Int32) := {
    resource :: Resource = (.value = 42)
    erased ::= to_virtual#(.abstract: Resettable)(.value = $&resource)
    reset(.self = $$&erased)
    status_code = 0
}
