math := import ("math/linear_algebra")

sum := #(.T: Type) (.left: &T, .right: &T) -> (.result: Add#(&T, &T).Result) {
    result = left + right
}

main := () -> (.status_code: Int32 = 0) {

    left :: math.Matrix#(.rows = 2, .cols = 2, .t: Int32) = (
        .values = (
            (1, 2),
            (3, 4)
        )
    )
    right :: math.Matrix#(.rows = 2, .cols = 2, .t: Int32) = (
        .values = (
            (5, 6),
            (7, 8)
        )
    )
    direct ::= &left + &right
    generic ::= sum(&left, &right)
    qualified ::= Add#(
        &math.Matrix#(.rows = 2, .cols = 2, .t: Int32),
        &math.Matrix#(.rows = 2, .cols = 2, .t: Int32)
    ).add(.left = &left, .right = &right)
    if direct.values[1][1] != 12 or generic.values[0][1] != 8 or qualified.values[1][0] != 10 {
        status_code = 1
    }
    empty :: math.Vector#(.n = 0, .t: Int32) = (.values = ())
    empty_sum ::= sum(&empty, &empty)
    if math.dot(.left = &empty_sum, .right = &empty_sum) != 0 { status_code = 2 }
}
