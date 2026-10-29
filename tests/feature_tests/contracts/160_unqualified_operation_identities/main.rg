Product#(.Left: Type, .Right: Type): Contract = (
    .Result   : Type
    .multiply : (.left: Left, .right: Right) -> (.result: Result)
)

implement Product#(Int32, UInt8) (
    .Result   : Type = Int32
    .multiply = (.left: Int32, .right: UInt8) -> (.result: Int32) {
        assume error_tracer ::= $&noop_error_tracer
        result = [left * right | convert#(.to: Int32)(_)]
    }
)

product := #(.A: Type, .B: Type) (.left: A, .right: B, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .result : Product#(A, B).Result
) {
    assume error_tracer
    result = multiply(left, right)
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    left: Int32 = 6
    right: UInt8 = 7
    if multiply(left, right).result != 42 { abort }
    if product(left, right).result != 42 { abort }
}
