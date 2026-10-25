main() -> (.status_code: Int32 = 0) := {
    value :: Int32 = 42
    reference := &value
    status_code = reference&
}
