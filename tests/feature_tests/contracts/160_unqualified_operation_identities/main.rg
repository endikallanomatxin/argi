Product#(.Left: Type, .Right: Type): Contract = (
    .Result   : Type
    .multiply : (.left: Left, .right: Right) -> (.result: Result)
)

implement Product#(Int32, UInt8) (
    .Result   : Type = Int32
    .multiply = (.left: Int32, .right: UInt8) -> (.result: Int32) {

        result = [left * right | convert#(.to: Int32)(_)]
    }
)

product := #(.A: Type, .B: Type) (.left: A, .right: B) -> (.result: Product#(A, B).Result) {

    result = multiply(left, right)
}

main := () -> (.status_code: Int32 = 0) {

    left: Int32 = 6
    right: UInt8 = 7
    if multiply(left, right).result != 42 { abort }
    if product(left, right).result != 42 { abort }
}
