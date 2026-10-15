Left: Type = (.value: Int32)
Right: Type = (.value: Int32)
implement Add#(Left, Right, (.left: &Left, .right: &Right, .bias: Int32 = 1)) (
    .Result: Type = Int32
    .add = (.args: (.left: &Left, .right: &Right, .bias: Int32 = 1)) -> (.result: Result) {
        result = args.left&.value + args.right&.value + args.bias
    }
)
implement Add#(Left, Right, (.left: &Left, .right: &Right, .offset: Int32 = 2)) (
    .Result: Type = Int32
    .add = (.args: (.left: &Left, .right: &Right, .offset: Int32 = 2)) -> (.result: Result) {
        result = args.left&.value + args.right&.value + args.offset
    }
)
main := () -> () {
    left ::= Left(1)
    right ::= Right(2)
    value ::= &left + &right
}
