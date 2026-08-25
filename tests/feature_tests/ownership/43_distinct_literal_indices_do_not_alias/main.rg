mix(.left: $&Int32, .right: $&Int32) -> () := {
    left& = 3
    right& = 4
}

main() -> (.status_code: Int32) := {
    values :: [2]Int32 = (1, 2)
    mix(.left = $&values[0], .right = $&values[1])
    status_code = values[0] + values[1] - 7
}
