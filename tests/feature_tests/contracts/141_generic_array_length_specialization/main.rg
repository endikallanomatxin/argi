Shape#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))
implement#(.N: Int, .T: Type) Shape#(Array#(.n = N, .t: T)) (
    .classify = (.value: &Array#(.n = N, .t: T)) -> (.result: Int32) { result = 1 }
)
implement#(.T: Type) Shape#(Array#(2, T)) (
    .classify = (.value: &Array#(2, T)) -> (.result: Int32) { result = 2 }
)
main := () -> (.status_code: Int32 = 0) {
    two: Array#(2, Int32) = (3, 4)
    three: Array#(3, Int32) = (3, 4, 5)
    if Shape#(Array#(2, Int32)).classify(&two).result != 2 { abort }
    if Shape#(Array#(3, Int32)).classify(&three).result != 1 { abort }
}
