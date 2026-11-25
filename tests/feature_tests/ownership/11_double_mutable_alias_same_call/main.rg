mix := (.left: $&Int32, .right: $&Int32) -> (.result: Int32) {
    left& = 21
    right& = right& * 2
    result = left&
}

main := () -> (.status_code: Int32) {
    value :: Int32 = 1
    status_code = mix(.left = $&value, .right = $&value)
}
