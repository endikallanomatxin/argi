Kind#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))

Pair#(.Left: Type, .Right: Type): Type = (.left: Left, .right: Right)

implement#(.A: Type, .B: Type) Kind#(Pair#(A, B))(
        .classify = (
                .value : &Pair#(A, B)
            ) -> (
                .result : Int32
            ) { result = 1 }
    )
implement#(.X: Type, .Y: Type) Kind#(Pair#(.Right: Y, .Left: X))(
        .classify = (
                .value : &Pair#(X, Y)
            ) -> (
                .result : Int32
            ) { result = 2 }
    )

main := () -> () {
    pair: Pair#(Int32, UInt8) = (.left = 1, .right = 2)
    Kind#(Pair#(Int32, UInt8)).classify(&pair)
}
