math := import ("math/linear_algebra")

main := () -> () {
    left: math.Matrix#(.rows = 1, .cols = 2, .t: Int32) = (.values = ((1, 2),))
    right: math.Matrix#(.rows = 2, .cols = 1, .t: UIntNative) = (
        .values = (
            (3),
            (4)
        )
    )
    result ::= &left * &right
}
