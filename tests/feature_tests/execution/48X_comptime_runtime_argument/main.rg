identity(.value: Int32) -> (.result: Int32) := { result = value }

main() -> (.status_code: Int32 = 0) := {
    value :: Int32 = 42
    status_code = #run identity(.value = value)
}
