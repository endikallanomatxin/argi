Pair<.Left: Type, .Right: Type>: Contract = (
    .classify : (.left: Left, .right: Right) -> (.result: Int32)
)

implement<.T: Type> Pair<T, Int32> (
    .classify = (.left: T, .right: Int32) -> (.result: Int32) { result = 1 }
)

implement<.U: Type> Pair<Int32, U> (
    .classify = (.left: Int32, .right: U) -> (.result: Int32) { result = 2 }
)

main := () -> () { Pair<Int32, Int32>.classify(3, 4) }
