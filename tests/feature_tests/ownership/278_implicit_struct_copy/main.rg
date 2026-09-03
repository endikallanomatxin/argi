Pair : Type = (
    .left: Int32
    .right: Int32
)

Pair implements ImplicitlyCopyable

main() -> (.status_code: Int32) := {
    first :: Pair = (.left = 20, .right = 1)
    second ::= first
    status_code = first.left + second.right - 21
}
