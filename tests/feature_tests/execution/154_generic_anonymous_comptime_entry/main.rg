calculate#(.T: Type, .n: Int32) := () -> (.result: T) {
    result = #run () -> (.value: T) { value = n }
}

selected#(.n: Int32) := () -> (.result: Int32) {
    result = #run () -> (.value: Int32) {
        #if n == 42 {
            value = #run () -> (.inner: Int32) { inner = n }
        } #else {
            value = 41
        }
    }
}

main() -> (.status_code: Int32) := {
    if calculate#(.T: Int8, .n = 41)() != 41 { abort }
    if calculate#(.T: Int32, .n = 41)() != 41 { abort }
    if selected#(.n = 41)() != 41 { abort }
    if selected#(.n = 42)() != 42 { abort }
    status_code = calculate#(.T: Int32, .n = 42)()
}
