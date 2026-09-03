Pair : Type = (
    .left: Int32
    .right: Int32
)

consume(.value: Int32) -> (.result: Int32) := {
    result = value
}

main() -> (.status_code: Int32) := {
    pair :: Pair = (.left = 1, .right = 2)
    moved ::= consume(.value = ~pair.left)
    pair.left = 3
    if pair.left == 3 and pair.right == 2 and moved == 1 {
        status_code = 0
    } else {
        status_code = 1
    }
}
