Concatenation#(.Left: Type, .Right: Type): Contract = (
    .join : (.left: Left, .right: Right, .allocator: $&Virtual#(Allocator)) -> (
        .result : Errable#(String, (..out_of_memory))
    )
)

concat := #(.Left: Type, .Right: Type) (
    .left: Left, .right: Right, .allocator: $&Virtual#(Allocator)
) -> (.result: Errable#(String, (..out_of_memory))) {

    result = ~Concatenation#(
        Left, Right
    ).join(.left = left, .right = right, .allocator = allocator)
}
