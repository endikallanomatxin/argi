Value := (.number: Int32)

implement Equal<Value, Value, (.left: &Value, .right: &Value, .bias: Int32 = reach bias)> (
    .equal = (.args: (.left: &Value, .right: &Value, .bias: Int32 = reach bias)) -> (.ok: Bool) {
        ok = args.left&.number == args.right&.number and args.bias == 7
    }
)

main := () -> () {
    left ::= Value(1)
    right ::= Value(1)
    same ::= &left == &right
}
