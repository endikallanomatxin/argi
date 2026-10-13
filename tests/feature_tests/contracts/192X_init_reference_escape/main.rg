Borrow: Type = (.value: &Int32)
implement Init#(Borrow) (
    .Args: Type = (.value: &Int32)
    .Result: Type = Borrow
    .init = (.args: Args) -> (.result: Result) { result.value = args.value }
)
escape := () -> (.result: Borrow) {
    local ::= 42
    result = Borrow(.value = &local)
}
main := () -> () { escape() }
