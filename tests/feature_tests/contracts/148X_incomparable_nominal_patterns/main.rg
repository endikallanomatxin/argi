Kind#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))

Pair#(.Left: Type, .Right: Type): Type = (.left: Left, .right: Right)

implement#(.T: Type) Kind#(Pair#(T, Int32))(
        .classify = (
                .value : &Pair#(T, Int32)
            ) -> (
                .result : Int32
            ) { result = 1 }
    )
implement#(.T: Type) Kind#(Pair#(Int32, T))(
        .classify = (
                .value : &Pair#(Int32, T)
            ) -> (
                .result : Int32
            ) { result = 2 }
    )

main := () -> () {
    pair: Pair#(Int32, Int32) = (.left = 1, .right = 2)
    Kind#(Pair#(Int32, Int32)).classify(&pair)
}
