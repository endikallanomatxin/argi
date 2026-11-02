Value := (.number: Int32)

implement Add#(&Value, &Value) (
    .Result: Type = Int32
    .add = (.left: &Value, .right: &Value) -> (.result: Bool) {
        result = true
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(2)
    result ::= &left + &right
}
