Point : Type = (
    .x: Int32,
    .y: Int32,
)

init(.p: $&Point, .x: Int32, .y: Int32) -> () := {
    p& = (.x=x, .y=y)
}

initialize_value(.p: $&Point, .x: Int32, .y: Int32) -> () := {
    p& = (.x=x, .y=y)
}

main () -> (.status_code: Int32) := {
    my_point :: Point = (.x=0, .y=0)
    init(.p = $&my_point, .x = 1, .y = 2)
    alias ::= &my_point
    initialize_value(.p = $&my_point, .x = 3, .y = 4)
    if alias&.x == 3 and alias&.y == 4 {
        status_code = 0
    } else {
        status_code = 1
    }
}
