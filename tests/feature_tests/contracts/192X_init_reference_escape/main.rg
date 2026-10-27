Borrow := (.value: &Int32)

BorrowInitArgs: Type = (.value: &Int32)

implement Init#(Borrow, BorrowInitArgs) (
    .Result : Type = Borrow

    .init = BorrowInitArgs -> (.result: Result) { result.value = value }
)

escape := () -> (.result: Borrow) {
    local ::= 42
    result = Borrow(.value = &local)
}

main := () -> () { escape() }
