Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

Inspect#(.Args: Type): Contract = (.inspect: (.args: Args) -> ())

implement#(.T: Type) Inspect#(Pair#(T, T)) (
    .inspect = (.args: Pair#(T, T)) -> () {}
)

main := () -> () {
    matching :: Pair#(Int32, Int32) = (.left = 1, .right = 2)
    Inspect#(Pair#(Int32, Int32)).inspect(matching)
    mismatched :: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
    Inspect#(Pair#(Int32, UInt8)).inspect(mismatched)
}
