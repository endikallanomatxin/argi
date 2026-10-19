broken := () -> (.value: Int32) {
    value = unknown_value
}

main := () -> (.status_code: Int32) {
    status_code = #run broken()
}
