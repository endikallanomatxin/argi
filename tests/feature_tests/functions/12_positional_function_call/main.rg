add_numbers := (.left: Int32, .right: Int32) -> (.sum: Int32) {
    sum = left + right
}

main := () -> (.status_code: Int32) {
    status_code = add_numbers(20, 22).sum
}
