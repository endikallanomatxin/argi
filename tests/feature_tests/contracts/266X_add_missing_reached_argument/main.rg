Value := (.number: Int32)

implement Add#(&Value, &Value) (
    .Result : Type = Int32
    .add    = (.left: &Value, .right: &Value, .bias: Int32 = reach bias) -> (
        .result : Result
    ) {
        result = left&.number + right&.number + bias
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(2)
    result ::= &left + &right
}
