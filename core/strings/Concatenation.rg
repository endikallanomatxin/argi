Concatenation#(.Left: Type, .Right: Type, .Provider: Type): Contract = (
    .join : (.left: Left, .right: Right, .allocator: $&Provider) -> (
        .result : Errable#(String, (..out_of_memory))
    )
)

concat#(.Left: Type, .Right: Type, .Provider: Type: Allocator) := (
    .left: Left, .right: Right, .allocator: $&Provider = reach allocator
) -> (.result: Errable#(String, (..out_of_memory))) {
    result = ~Concatenation#(
        Left, Right, Provider
    ).join(.left = left, .right = right, .allocator = allocator)
}
