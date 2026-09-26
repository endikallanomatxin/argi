test assertion_failure(.system: System) -> !() := {
    testing.expect(.condition = false)!
}
