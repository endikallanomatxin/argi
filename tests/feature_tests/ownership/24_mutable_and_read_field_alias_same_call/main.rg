Pair : Type = (
    .left: Int32
    .right: Int32
)

mix(.target: $&Int32, .reader: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    pair :: Pair = (
        .left = 1,
        .right = 2,
    )
    mix(.target = $&pair.left, .reader = &pair.left)
    status_code = 0
}
