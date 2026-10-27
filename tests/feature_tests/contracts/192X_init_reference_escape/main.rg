Borrow := (.value: &Int32)

implement Init#(Borrow) (
    .init = (.value: &Int32) -> (.result: Borrow) { result.value = value }
)

escape := () -> (.result: Borrow) {
    local ::= 42
    result = Borrow(.value = &local)
}

main := () -> () { escape() }
