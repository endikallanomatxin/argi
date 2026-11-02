Pair#(.Left: Type, .Right: Type): Contract = (
    .Result   : Type
    .classify : (.left: Left, .right: Right) -> (.result: Result)
)

implement#(.A: Type, .B: Type) Pair#(A, B) (
    .Result   : Type = Int32
    .classify = (.left: A, .right: B) -> (.result: Result) { result = 1 }
)

implement#(.T: Type) Pair#(T, T) (
    .Result   : Type = Int32
    .classify = (.left: T, .right: T) -> (.result: Result) { result = 2 }
)

main := () -> (.status_code: Int32 = 0) {
    if Pair#(Int32, Int32).classify(3, 4).result != 2 { abort }
    if Pair#(Int32, UInt8).classify(3, 4).result != 1 { abort }
}
