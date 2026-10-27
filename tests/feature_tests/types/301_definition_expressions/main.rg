Point := (
    .x : Int32
    .y : Int32 = 2
)

Box := #(.T: Type) (
    .value : T
)

identity := #(.T: Type) (.value: T) -> (.result: T) {
    result = value
}

main := () -> (.status_code: Int32 = 0) {
    point: Point = (.x = 40)
    box: Box#(Int32) = (.value = identity#(.T: Int32)(.value = point.x + point.y).result)
    if box.value != 42 { abort }
    known: Int32 = #run () -> (.result: Int32) {
        result = identity#(Int32)(.value = 42).result
    }
    if known != box.value { abort }
}
