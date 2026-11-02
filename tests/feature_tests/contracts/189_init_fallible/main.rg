Point := (._x: Int32)

PointInitArgs: Type = (
    .x : Int32
)

implement Init#(Point, PointInitArgs) (
    .Result : Type = Errable#(Point, (..invalid_point))

    .init = PointInitArgs -> (.result: Result) {

        if x < 0 {
            result = ..error(.reason = ..invalid_point)
            return
        }
        result = ..ok(._x = x)
    }
)

main := () -> (.status_code: Int32 = 0) {

    point ::= unwrap_or_abort(.value = Point(.x = 10))
    if point._x != 10 { abort }
    match Point(.x = -1) {
        ..ok _ { abort } ..error error { if error.reason != ..invalid_point { abort } }
    }
}
