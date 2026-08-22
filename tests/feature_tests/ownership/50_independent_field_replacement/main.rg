Pair : Type = (
    .left: Int32
    .right: Int32
)

read(.value: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    pair :: Pair = (.left = 1, .right = 2)
    pointer := &pair.left
    pair.right = 3
    read(.value = pointer)
    status_code = 0
}
