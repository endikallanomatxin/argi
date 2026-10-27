Point := (
    .x : Int32,
    .y : Int32,
)

PointInitArgs: Type = (.x: Int32, .y: Int32)

implement Init#(Point, PointInitArgs) (
    .Result : Type = Point

    .init = PointInitArgs -> (.result: Result) {
        _init_x ::= ~x
        _init_y ::= ~y

        result = (.x = _init_x, .y = _init_y)
    }
)

main := () -> (.status_code: Int32) {
    point := Point(20, .y = 22)
    status_code = point.x + point.y
}
