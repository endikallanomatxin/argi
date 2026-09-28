Pair : Type = (
    .left: &Int32
    .right: &Int32
)

choose(.change_left: Bool) -> (.result: Int32) := {
    first :: Int32 = 1
    second :: Int32 = 2
    third :: Int32 = 3
    pair :: Pair = (.left = &first, .right = &second)
    if change_left {
        pair.left = &third
    } else {
        pair.right = &third
    }
    copied ::= pair
    result = copied.left& + copied.right&
}

main() -> (.status_code: Int32) := {
    left_result ::= choose(.change_left = true)
    right_result ::= choose(.change_left = false)
    if left_result == 5 and right_result == 4 {
        status_code = 0
    } else {
        status_code = 1
    }
}
