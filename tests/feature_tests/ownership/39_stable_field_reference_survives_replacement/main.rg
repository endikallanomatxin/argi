Pair : Type = (
    .left: Int32
    .right: Int32
)

main() -> (.status_code: Int32) := {
    pair :: Pair = (.left = 1, .right = 2)
    pointer ::= &pair.left
    pair.left = 3
    status_code = pointer& - 3
}
