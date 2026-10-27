Point := (
    .x: Int32,
    .y: Int32,
)

implement Init#(Point) (
    .init = (.sum: Int32) -> (.result: Point) {
        _init_sum ::= ~sum

        result = (
            .x = _init_sum,
            .y = 0,
        )
    }
)

main := () -> (.status_code: Int32)  {
    point := Point(.x = 1, .y = 2)
    status_code = point.x + point.y
}
