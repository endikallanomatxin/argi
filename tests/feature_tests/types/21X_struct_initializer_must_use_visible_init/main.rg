Point : Type = (
    .x: Int32,
    .y: Int32,
)

implement Init#(Point, (.sum: Int32)) (
    .Result: Type = Point
    .init = (.args: (.sum: Int32)) -> (.result: Result) {
        sum ::= ~args.sum

        result = (
            .x = sum,
            .y = 0,
        )
    }
)

main() -> (.status_code: Int32) := {
    point := Point(.x = 1, .y = 2)
    status_code = point.x + point.y
}
