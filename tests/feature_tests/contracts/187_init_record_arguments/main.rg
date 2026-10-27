Point := (._x: Int32, ._y: Int32)

implement Init#(Point) (
    .init = (.x: Int32, .y: Int32 = 0) -> (.result: Point) {
        result = (._x = x, ._y = y)
    }
)

main := () -> (.status_code: Int32 = 0) {
    point ::= Point(.x = 10)
    if point._x != 10 or point._y != 0 { abort }
}
