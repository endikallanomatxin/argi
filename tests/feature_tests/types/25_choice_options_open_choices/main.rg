..file_not_found
..permission_denied

main() -> (.status_code: Int32) := {
    reason : (..file_not_found, ..permission_denied) = ..permission_denied

    if is(.value = reason, .variant = ..permission_denied) {
        status_code = 0
    } else {
        status_code = 1
    }
}
