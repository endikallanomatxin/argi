Point : Type = (
    .x: Int32,
    .y: Int32,
)

init(.p: $&Point, .x: Int32, .y: Int32) -> () := {
    p& = (.x = x, .y = y)
}

main() -> (.status_code: Int32) := {
    point := Point(20, .y = 22)
    status_code = point.x + point.y
}
