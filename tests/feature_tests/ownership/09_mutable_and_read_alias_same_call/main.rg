mix(.target: $&Int32, .reader: &Int32) -> () := {}

main() -> (.status_code: Int32) := {
    value :: Int32 = 1
    mix(.target = $&value, .reader = &value)
    status_code = 0
}
