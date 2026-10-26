Value := (.number: Int32)

implement Add<Value, Value, (.left: &Value, .right: &Value, .bias: Int32 = reach bias)> (
    .Result : Type = Int32
    .add    = (.args: (.left: &Value, .right: &Value, .bias: Int32 = reach bias)) -> (
        .result : Result
    ) {
        result = args.left&.number + args.right&.number + args.bias
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(2)
    result ::= &left + &right
}
