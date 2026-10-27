Kind#(.Value: Type): Contract = (.classify: (.value: &Value) -> (.result: Int32))

Pair := #(.Left: Type, .Right: Type) (.left: Left, .right: Right)

Window := #(.Count: Int, .Element: Type) (.value: Element)

implement#(.T: Type) Kind#(Window#(2, Pair#(T, T))) (
    .classify = (.value: &Window#(2, Pair#(T, T))) -> (.result: Int32) { result = 3 }
)

implement#(.N: Int, .T: Type) Kind#(Window#(.Element: T, .Count: N)) (
    .classify = (.value: &Window#(N, T)) -> (.result: Int32) { result = 2 }
)

implement#(.T: Type) Kind#(T) (
    .classify = (.value: &T) -> (.result: Int32) { result = 1 }
)

main := () -> (.status_code: Int32 = 0) {
    repeated: Window#(2, Pair#(Int32, Int32)) = (.value = (.left = 1, .right = 2))
    distinct: Window#(2, Pair#(Int32, UInt8)) = (.value = (.left = 1, .right = 2))
    if Kind#(Window#(2, Pair#(Int32, Int32))).classify(&repeated).result != 3 { abort }
    if Kind#(Window#(2, Pair#(Int32, UInt8))).classify(&distinct).result != 2 { abort }
    if Kind#(Int32).classify(&repeated.value.left).result != 1 { abort }
}
