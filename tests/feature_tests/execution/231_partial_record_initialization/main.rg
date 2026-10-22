Pair: Type = (.left: Int32, .right: Int32)

unused() -> (.result: Pair) := { result = (.left = 0) }

main() -> (.status_code: Int32) := {
    pair :: Pair
    pair.left = 20
    pair.right = 22
    status_code = pair.left + pair.right
}
