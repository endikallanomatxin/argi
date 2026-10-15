ShapePair#(.Left: Type, .Right: Type): Contract = (
    .classify: (.left: &Left, .right: &Right) -> (.result: Int32)
)
implement#(.N: Int, .M: Int, .A: Type, .B: Type) ShapePair#(Array#(.n = N, .t: A), Array#(.n = M, .t: B)) (
    .classify = (.left: &Array#(.n = N, .t: A), .right: &Array#(.n = M, .t: B)) -> (.result: Int32) { result = 1 }
)
implement#(.N: Int, .A: Type, .B: Type) ShapePair#(Array#(.n = N, .t: A), Array#(.n = N, .t: B)) (
    .classify = (.left: &Array#(.n = N, .t: A), .right: &Array#(.n = N, .t: B)) -> (.result: Int32) { result = 2 }
)
main := () -> (.status_code: Int32 = 0) {
    two: Array#(2, Int32) = (3, 4)
    other: Array#(2, UInt8) = (5, 6)
    three: Array#(3, Int32) = (3, 4, 5)
    if ShapePair#(Array#(2, Int32), Array#(2, UInt8)).classify(&two, &other).result != 2 { abort }
    if ShapePair#(Array#(2, Int32), Array#(3, Int32)).classify(&two, &three).result != 1 { abort }
}
