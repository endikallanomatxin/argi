Pair : Type = (
    .left: Int32
    .right: Int32
)

mix(.target: $$&Int32, .snapshot: Int32) -> () := {
    target& = snapshot
}

main() -> (.status_code: Int32) := {
    pair :: Pair = (
        .left = 1,
        .right = 7,
    )
    mix(.target = $$&pair.left, .snapshot = pair.right)
    status_code = pair.left
}
