math := import ("math/linear_algebra")

main := () -> () {
    left :: math.Vector#(.n = 2, .t: Int32) = (.values = (0, 0))
    right :: math.Vector#(.n = 3, .t: Int32) = (.values = (0, 0, 0))
    result ::= &left + &right
}
