Owner : Type = (.value: Int32)
Owner deinit(.self: $&Owner) -> () := {}
Holder : Type = (.reference: ?&Int32)
Holder implements ImplicitlyCopyable
extract(.holder: &Holder) -> (.reference: &Int32) := {
    match holder&.reference {
        ..none { abort }
        ..some payload { reference = payload.value }
    }
}
forward(.reference: &Int32) -> (.result: &Int32) := {
    local :: Holder = (.reference = ..some(.value = reference))
    alias ::= &local
    result = extract(.holder = alias).reference
}
read(.reference: &Int32) -> (.value: Int32) := { value = reference& }
main() -> (.status_code: Int32 = 0) := {
    owner :: Owner = (.value = 7)
    borrowed ::= forward(.reference = &owner.value).result
    deinit(.self = $&owner)
    observed ::= read(.reference = borrowed).value
}
