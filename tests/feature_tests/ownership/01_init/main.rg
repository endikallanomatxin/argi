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

initialize_value := (.p: $&Point, .x: Int32, .y: Int32) -> () {
    p&= (.x = x, .y = y)
}

main := () -> (.status_code: Int32) {
    my_point :: Point = (.x = 0, .y = 0)
    my_point = Point(.x = 1, .y = 2)
    alias ::= &my_point
    initialize_value(.p = $&my_point, .x = 3, .y = 4)
    if alias&.x == 3 and alias&.y == 4 {
        status_code = 0
    } else {
        status_code = 1
    }
}
