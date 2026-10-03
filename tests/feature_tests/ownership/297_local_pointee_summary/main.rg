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
forward_replaced(.old: &Int32, .current: &Int32) -> (.result: &Int32) := {
    local :: Holder = (.reference = ..some(.value = old))
    alias ::= &local
    local = (.reference = ..some(.value = current))
    result = extract(.holder = alias).reference
}
main() -> (.status_code: Int32 = 0) := {
    owner :: Owner = (.value = 7)
    borrowed ::= forward(.reference = &owner.value).result
    if read(.reference = borrowed).value != 7 { status_code = 1 }
    previous :: Owner = (.value = 2)
    latest :: Owner = (.value = 9)
    replaced ::= forward_replaced(.old = &previous.value, .current = &latest.value).result
    deinit(.self = $&previous)
    if read(.reference = replaced).value != 9 { status_code = 2 }
    deinit(.self = $&latest)
    deinit(.self = $&owner)
}
