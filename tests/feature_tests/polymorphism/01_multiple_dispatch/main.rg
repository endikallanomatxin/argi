Selection<.Value: Type>: Contract = (
    .choose : (.p: &Value) -> (.r: Int32)
)

implement<.Value: Type> Selection<Value> (
    .choose = (.p: &Value) -> (.r: Int32) { r = 1 }
)

implement Selection<Int32> (
    .choose = (.p: &Int32) -> (.r: Int32) { r = 2 }
)

main := () -> (.status_code: Int32) {
    i: Int32 = 0
    status_code = choose(.p = &i).r
}
