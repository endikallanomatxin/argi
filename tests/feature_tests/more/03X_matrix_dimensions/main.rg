math := import ("math/linear_algebra")
main() -> (.status_code: Int32 = 0) := {
    left: math.Matrix#(.rows = 2, .cols = 3, .t: Int32) = (.values = ((1, 2, 3), (4, 5, 6)))
    right: math.Matrix#(.rows = 2, .cols = 2, .t: Int32) = (.values = ((1, 2), (3, 4)))
    math.multiply(.left = &left, .right = &right)
}
