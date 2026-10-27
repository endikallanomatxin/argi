Point := (._x: Int32, ._y: Int32)

PointInitArgs: Type = (.x: Int32, .y: Int32 = 0)

implement Init#(Point, PointInitArgs) (
    .Result : Type = Point

    .init = PointInitArgs -> (.result: Result) {
        result = (._x = x, ._y = y)
    }
)

main := () -> (.status_code: Int32 = 0) {
    point ::= Point(.x = 10)
    if point._x != 10 or point._y != 0 { abort }
}
