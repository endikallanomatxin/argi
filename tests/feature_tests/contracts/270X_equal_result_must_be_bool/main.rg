Value := (.number: Int32)

implement Equal#(Value, Value, (.left: &Value, .right: &Value)) (
    .equal = (.args: (.left: &Value, .right: &Value)) -> (.ok: Int32) { ok = 1 }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(1)
    same ::= &left == &right
}
