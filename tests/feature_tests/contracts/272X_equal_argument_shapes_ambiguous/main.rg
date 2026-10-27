Value := (.number: Int32)

implement Equal#(&Value, &Value) (
    .equal = (.left: &Value, .right: &Value, .bias: Int32 = 1) -> (.ok: Bool) {
        ok = true
    }
)

implement Equal#(&Value, &Value) (
    .equal = (.left: &Value, .right: &Value, .offset: Int32 = 2) -> (.ok: Bool) {
        ok = false
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(1)
    same ::= &left == &right
}
