test selected(.system: System) -> !() := {
    #if 1 < 2 {
        testing.expect(.condition = true)!
    } #else {
        unavailable_test_branch()
    }
}
