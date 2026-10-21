calculate#(.T: Type, .n: Int32) := () -> (.result: T) {
    result = #run () -> (.value: T) { value = n }
}

main() -> (.status_code: Int32) := {
    if calculate#(.T: Int8, .n = 41)() != 41 { abort }
    if calculate#(.T: Int32, .n = 41)() != 41 { abort }
    status_code = calculate#(.T: Int32, .n = 42)()
}
