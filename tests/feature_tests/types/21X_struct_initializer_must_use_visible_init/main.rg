Point : Type = (
    .x: Int32,
    .y: Int32,
)

init(.p: $&Point, .sum: Int32) -> () := {
    p& = (
        .x = sum,
        .y = 0,
    )
}

main() -> (.status_code: Int32) := {
    point := Point(.x = 1, .y = 2)
    status_code = point.x + point.y
}
