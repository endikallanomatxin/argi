Point : Type = (
    .x: Int32
    .y: Int32
)

add_one (.i: Int32) -> (.o: Int32) := {
    o = i + 1
}

sum_point (.a: Int32, .b: Int32) -> (.r: Int32) := {
    r = a + b
}

main () -> (.status_code: Int32) := {
    p : Point = (
        .x = 20
        .y = 21
    )

    total : Int32 = p | sum_point(_.x, _.y)
    status_code = total | add_one
}
