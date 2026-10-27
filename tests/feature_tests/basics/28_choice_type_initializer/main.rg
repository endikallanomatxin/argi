..first_reason
..second_reason

Reasons := (..first_reason, ..second_reason)

Alias := Reasons

main := () -> (.status_code: Int32 = 0) {
    value: Alias = ..first_reason
    match value {
        ..first_reason {}
        ..second_reason { abort }
    }
}
