Owner := (.value: Int32)

implement Deinit#(Owner) (
    .deinit = (.self: $&Owner) -> () {

    }
)

Holder := (.reference: ?&Int32)

read := (.holder: &Holder) -> (.value: Int32) {
    match holder&.reference {
        ..none { abort }
        ..some payload { value = payload.value&}
    }
}

main := () -> (.status_code: Int32 = 0) {
    owner :: Owner = (.value = 7)
    holder :: Holder = (.reference = ..some(.value = &owner.value))
    deinit(.self = $&owner)
    observed ::= read(.holder = &holder).value
}
