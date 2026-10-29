Point := (._x: Int32)

PointInitArgs: Type = (
    .x            : Int32,
    .error_tracer : $&Virtual#(ErrorTracer)
)

implement Init#(Point, PointInitArgs) (
    .Result : Type = Errable#(Point, (..invalid_point))

    .init = PointInitArgs -> (.result: Result) {
        assume error_tracer

        if x < 0 {
            result = ..error(.reason = ..invalid_point)
            return
        }
        result = ..ok(._x = x)
    }
)

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    point ::= unwrap_or_abort(.value = Point(.x = 10))
    if point._x != 10 { abort }
    match Point(.x = -1) {
        ..ok _ { abort } ..error error { if error.reason != ..invalid_point { abort } }
    }
}
