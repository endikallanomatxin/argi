Point : Type = (
    .x: Int32,
    .y: Int32,
)

main() -> (.status_code: Int32) := {
    point := Point(.x = 11, .y = 31)
    status_code = point.x + point.y
}
