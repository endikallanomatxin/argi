Pair := (
    .left  : Int32
    .right : Int32
)

implement ImplicitlyCopyable#(Pair) ()

main := () -> (.status_code: Int32) {
    first :: Pair = (.left = 20, .right = 1)
    second ::= first
    status_code = first.left + second.right - 21
}
