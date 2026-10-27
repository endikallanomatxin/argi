Point := (
    .x: Int32,
    .y: Int32,
)

implement Init#(Point, (.x: Int32, .y: Int32)) (
    .Result: Type = Point
    .init = (.args: (.x: Int32, .y: Int32)) -> (.result: Result) {
        x ::= ~args.x
        y ::= ~args.y

        result = (.x = x, .y = y)
    }
)

main := () -> (.status_code: Int32)  {
    point := Point(20, 22)
    status_code = point.x + point.y
}
