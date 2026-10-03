Point : Type = (
    .x: Int32,
    .y: Int32,
)

Point init(.x: Int32, .y: Int32) -> (.result: Point) := {
    result = (.x = x, .y = y)
}

main() -> (.status_code: Int32) := {
    point := Point(20, .y = 22)
    status_code = point.x + point.y
}
