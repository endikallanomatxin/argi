Value := (.number: Int32)

implement Equal#(&Value, &Value) (
    .equal = (.left: &Value, .right: &Value, .bias: Int32 = reach bias) -> (.ok: Bool) {
        ok = left&.number == right&.number and bias == 7
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(1)
    same ::= &left == &right
}
