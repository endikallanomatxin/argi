math := import ("math/linear_algebra")

main := () -> () {
    left ::= math.Diagonal<.n = 2, .t: Int32>(.values = (2, 3))
    right ::= math.Diagonal<.n = 3, .t: Int32>(.values = (4, 5, 6))
    result ::= &left * &right
}
