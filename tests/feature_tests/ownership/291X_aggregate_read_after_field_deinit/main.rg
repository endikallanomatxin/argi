Thing : Type = (
    .value: Int32
)

Thing deinit(.self: $&Thing) -> () := {
}

Pair : Type = (
    .left: Thing
    .right: Int32
)

main() -> (.status_code: Int32) := {
    pair :: Pair = (.left = Thing(.value = 1), .right = 2)
    deinit(.self = $&pair.left)
    copied ::= ~pair
    status_code = copied.right
}
