record ::= (.inner = (.number = 9))

main := () -> (.status_code: Int32 = 0) {
    if record.inner.number != 9 { return 1 }
}
