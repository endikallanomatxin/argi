Point := (._x: Int32)

implement Init#(Point) (
    .init = (.x: Int32) -> (.result: Errable#(Point, (..invalid_point))) {
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
