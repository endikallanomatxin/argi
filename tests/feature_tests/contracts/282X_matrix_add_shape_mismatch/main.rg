math := import ("math/linear_algebra")

main := () -> () {
    left :: math.Matrix<.rows = 2, .cols = 3, .t: Int32> = (
        .values = (
            (0, 0, 0),
            (0, 0, 0)
        )
    )
    right :: math.Matrix<.rows = 3, .cols = 2, .t: Int32> = (
        .values = (
            (0, 0),
            (0, 0),
            (0, 0)
        )
    )
    result ::= &left + &right
}
