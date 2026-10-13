Left: Type = (.value: Int32)
Right: Type = (.value: Int32)
implement Add#(Left, Right, (.left: &Left, .right: &Right)) (
    .Result: Type = &Int32
    .add = (.args: (.left: &Left, .right: &Right)) -> (.result: Result) {
        result = &args.left&.value
    }
)
escape := () -> (.result: &Int32) {
    left ::= Left(7)
    right ::= Right(9)
    result = &left + &right
}
main := () -> () { value ::= escape() }
