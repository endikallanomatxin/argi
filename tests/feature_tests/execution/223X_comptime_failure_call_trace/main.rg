fail() -> (.result: Int32 = 0) := { abort }

middle() -> (.result: Int32) := { result = fail() }

main() -> (.status_code: Int32) := {
    status_code = #run () -> (.value: Int32) { value = middle() }
}
