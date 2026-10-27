Pair#(.Left: Type, .Right: Type): Contract = (
    .combine : (.left: Left, .right: Right) -> (.result: Int32)
)

implement#(.T: Type) Pair#(T, Int32) (
    .combine = (.left: T, .right: Int32) -> (.result: Int32) { result = 1 }
)

implement#(.T: Type) Pair#(Int32, T) (
    .combine = (.left: Int32, .right: T) -> (.result: Int32) { result = 2 }
)

main := () -> () {
    left: Int32 = 1
    right: Int32 = 2
    combine(left, right)
}
