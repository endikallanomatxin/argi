calls :: Int32 = 0

Plain := (.value: Int32)

deinit := (.self: $&Plain) -> () {
    calls = calls + 1
    self&.value = self&.value + 1
}

exercise := () -> () {
    value ::= Plain(.value = 7)
    deinit(.self = $&value)
    deinit(.self = $&value)
    if value.value != 9 { abort }
    unused ::= Plain(.value = 0)
}

main := () -> (.status_code: Int32 = 0) {
    exercise()
    if calls != 2 { status_code = 1 }
}
