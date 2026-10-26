calls :: Int32 = 0

next_value := () -> (.result: Int32) {
    calls = calls + 1
    result = 20 + calls
}

main := () -> (.status_code: Int32) {
    values: [2](.marker: Int32, .answer: Int32 = next_value()) = (
        (.marker = 1),
        (.marker = 2)
    )
    if calls != 2 { abort }
    status_code = values[0].answer + values[1].answer - 1
}
