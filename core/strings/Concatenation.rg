Concatenation#(.Left: Type, .Right: Type, .Provider: Type): Contract = (
    .join : (
        .left         : Left,
        .right        : Right,
        .allocator    : $&Provider,
        .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
            NoopErrorTracer()
            | to_virtual#(.contract: ErrorTracer)($&_)
            | $&_
        ]
    ) -> (.result: Errable#(String, (..out_of_memory)))
)

concat := #(.Left: Type, .Right: Type, .Provider: Type: Allocator) (
    .left         : Left,
    .right        : Right,
    .allocator    : $&Provider,
    .error_tracer : $&Virtual#(.contract: ErrorTracer) = [
        NoopErrorTracer()
        | to_virtual#(.contract: ErrorTracer)($&_)
        | $&_
    ]
) -> (.result: Errable#(String, (..out_of_memory))) {
    assume error_tracer

    result = ~Concatenation#(
        Left, Right, Provider
    ).join(.left = left, .right = right, .allocator = allocator)
}
