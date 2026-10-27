Point := (
    .x : Int32,
    .y : Int32,
)

implement Init#(Point) (
    .init = (.x: Int32, .y: Int32) -> (.result: Point) {
        _init_x ::= ~x
        _init_y ::= ~y

        result = (.x = _init_x, .y = _init_y)
    }
)

main := () -> (.status_code: Int32) {
    point := Point(20, .y = 22)
    status_code = point.x + point.y
}
