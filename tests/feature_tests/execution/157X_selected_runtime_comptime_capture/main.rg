choose := #(.n: Int32) (.runtime_value: Int32) -> (.result: Int32) {
    result = #run () -> (.value: Int32) {
        #if n == 42 { value = n } #else { value = runtime_value }
    }
}

main := () -> (.status_code: Int32) {
    status_code = choose#(.n = 41)(.runtime_value = 7)
}
