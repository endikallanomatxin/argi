Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

Inspect#(.Args: Type): Contract = (.inspect: (.args: Args) -> ())

implement#(.T: Type) Inspect#(Pair#(Int32, T)) (
    .inspect = (.args: Pair#(Int32, T)) -> () {}
)

implement#(.T: Type) Inspect#(Pair#(T, UInt8)) (
    .inspect = (.args: Pair#(T, UInt8)) -> () {}
)

main := () -> () {
    args :: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
    Inspect#(Pair#(Int32, UInt8)).inspect(args)
}
