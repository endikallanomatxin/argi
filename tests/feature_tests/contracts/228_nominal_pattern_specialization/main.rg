Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

Inspect#(.Args: Type): Contract = (
    .inspect : (.args: Args) -> (.result: Int32)
)

implement#(.T: Type, .U: Type) Inspect#(Pair#(T, U)) (
    .inspect = (.args: Pair#(T, U)) -> (.result: Int32) { result = 1 }
)

implement#(.T: Type) Inspect#(Pair#(Int32, T)) (
    .inspect = (.args: Pair#(Int32, T)) -> (.result: Int32) { result = 2 }
)

implement#(.T: Type) Inspect#(Pair#(T, T)) (
    .inspect = (.args: Pair#(T, T)) -> (.result: Int32) { result = 3 }
)

main := () -> (.status_code: Int32 = 0) {
    first :: Pair#(UInt8, UInt16) = (.left = 1, .right = 2)
    second :: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
    repeated :: Pair#(UInt8, UInt8) = (.left = 1, .right = 2)
    if Inspect#(Pair#(UInt8, UInt16)).inspect(first) != 1 { abort }
    if Inspect#(Pair#(Int32, UInt8)).inspect(second) != 2 { abort }
    if Inspect#(Pair#(UInt8, UInt8)).inspect(repeated) != 3 { abort }
}
