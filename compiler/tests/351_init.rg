Point : Type = (
    .x: Int32,
    .y: Int32,
)

init(.p: $&Point, .x: Int32, .y: Int32) -> () := {
    p& = (.x=x, .y=y)
}

main () -> (.status_code: Int32) := {
    my_point := Point(.x=1, .y=2)
    status_code = 0
}

