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
    status_code = pair.left + pair.right - moved
}
