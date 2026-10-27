Borrow#(.Target: Type): Contract = (.borrow: _)

Box := (.value: Int32)

implement Borrow#(Box) (
    .borrow = () -> (.result: &Int32) {
        local: Box = (.value = 42)
        result = &local.value
    }
)

main := () -> (.status_code: Int32) {
    reference ::= Borrow#(Box).borrow()
    status_code = reference&
}
