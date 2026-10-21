fail() -> (.result: Int32 = 0) := { abort }

main() -> (.status_code: Int32 = 0) := {
    status_code = #run () -> (.value: Int32) { value = fail() }
}
