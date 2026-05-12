test assertion_failure(.system: System = System()) -> !() := {
    testing.expect(.condition = false)!
}
