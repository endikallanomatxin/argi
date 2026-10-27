Value := (.number: Int32)

implement Equal#(&Value, &Value) (
    .equal = (.left: &Value, .right: &Value) -> (.ok: Int32) { ok = 1 }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(1)
    same ::= &left == &right
}
