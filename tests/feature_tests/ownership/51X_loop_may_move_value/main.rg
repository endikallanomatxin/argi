Pair : Type = (.left: Int32, .right: Int32)
consume(.value: Int32) -> () := {}

main(.condition: Bool = false) -> (.status_code: Int32) := {
    pair :: Pair = (.left = 1, .right = 2)
    while condition {
        consume(.value = ~pair.left)
    }
    status_code = pair.left
}
