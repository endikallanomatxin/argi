mix(.target: $&Int32, .snapshot: Int32) -> () := {}

main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    mix(.target = $&value, .snapshot = value)
    status_code = 0
}
