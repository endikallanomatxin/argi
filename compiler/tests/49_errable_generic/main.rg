main () -> (.status_code: Int32) := {
    result : Errable#(.t: Int32, .e: Char) = ..error(.value = 'x')

    if is(.value = result, .variant = ..error) {
        payload := result..error
        status_code = 0
    } else {
        status_code = 1
    }
}
