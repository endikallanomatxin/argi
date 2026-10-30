main := (.system: System) -> (.status_code: Int32) {

    assume ffi := system.ffi
    file ::= File()
    path ::= from_literal(.data = "tests/feature_tests/io/13_file_open_error/build/missing.txt")

    open_result ::= open(.p = $&file, .path = path, .mode = ..read)
    if is(.value = open_result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = open_result ..error.reason, .variant = ..file_open_failed) {
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
