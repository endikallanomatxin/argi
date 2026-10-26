math := import ("math")

main := () -> (.status_code: Int32 = 0) {
    matrix: math.linear_algebra.Matrix<.rows = 2, .cols = 2, .t: Int32> = (
        .values = (
            (1, 2),
            (3, 4)
        )
    )
    if matrix.values[1][1] != 4 { return 1 }
}
