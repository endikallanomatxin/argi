test simple_pass(.system: System = System()) -> !() := {
    testing.expect(.condition = true)!
}
