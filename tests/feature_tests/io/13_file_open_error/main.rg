main() -> (.status_code: Int32) := {
    file ::= File(.handle = 0, .should_close = 0 == 1)
    path ::= from_literal(.data = "tests/feature_tests/io/13_file_open_error/build/missing.txt")

    open_result ::= open_read(.p = $&file, .path = path)
    if is(.value = open_result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = open_result..error.reason, .variant = ..file_open_failed) {
    } else {
        status_code = 2
        return
    }

    if is_open(.self = &file).ok {
        status_code = 3
        return
    }

    status_code = 0
}
