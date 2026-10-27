subtract_numbers := (.left: Int32, .right: Int32) -> (.diff: Int32) {
    diff = left - right
}

main := () -> (.status_code: Int32) {
    status_code = subtract_numbers(44, .right = 2).diff
}
