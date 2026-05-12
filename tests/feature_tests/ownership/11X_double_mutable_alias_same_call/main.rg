mix(.left: $&Int32, .right: $&Int32) -> () := {}

main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    mix(.left = $&value, .right = $&value)
    status_code = 0
}
