Left: Type = (.value: Int32)
Right: Type = (.value: Int32)
implement Add#(Left, Right, (.left: &Left, .right: &Right)) (
    .Result: Type = &Int32
    .add = (.args: (.left: &Left, .right: &Right)) -> (.result: Result) {
        result = &args.left&.value
    }
)
main := () -> (.status_code: Int32 = 0) {
    left ::= Left(7)
    right ::= Right(9)
    value ::= &left + &right
    if value& != 7 { status_code = 1 }
}
