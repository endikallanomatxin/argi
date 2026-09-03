..file_not_found
..permission_denied

read_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found))) := {
    result = ..error(.reason = ..file_not_found)
}

load_file() -> (.result: Errable#(.t: Int32, .reasons: (..file_not_found, ..permission_denied))) := {
    value := read_file()!
    result = ..ok value
}

main() -> (.status_code: Int32) := {
    result := load_file()
    if is(.value = result, .variant = ..error) {
        err ::= &result..error
        if is(.value = err&.reason, .variant = ..file_not_found) {
            status_code = 0
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
