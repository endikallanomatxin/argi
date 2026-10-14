Selection#(.Left: Type, .Right: Type): Contract = (
    .choose2: (.a: &Left, .b: &Right) -> (.r: Int32)
)
implement#(.Left: Type) Selection#(Left, Int32) (
    .choose2 = (.a: &Left, .b: &Int32) -> (.r: Int32) { r = 10 }
)
implement#(.Right: Type) Selection#(Int32, Right) (
    .choose2 = (.a: &Int32, .b: &Right) -> (.r: Int32) { r = 20 }
)
main := () -> (.status_code: Int32) {
    i: Int32 = 5
    status_code = choose2(.a = &i, .b = &i).r
}
