..test_error

main () -> (.status_code: Int32) := {
    result : Errable#(.t: Int32, .reasons: (..test_error)) = ..error(.reason = ..test_error)

    if is(.value = result, .variant = ..error) {
        payload ::= &result..error
        status_code = 0
    } else {
        status_code = 1
    }
}
