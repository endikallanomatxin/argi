Point : Type = (
    .x: Int32,
    .y: Int32,
)

init(.p: &Point, .x: Int32, .y: Int32) -> () := {
    -- TODO: Make the pointer mutable when implemented
    p = (.x=x, .y=y)
}

main () -> (.status_code: Int32) := {
    my_point := Point(.x=1, .y=2)
    puts(.string="Hello world!")
    status_code = 0
}

