main(.system: System = System()) -> (.status_code: Int32) := {
    missing_path ::= from_literal(.data = "tests/feature_tests/system/26_file_system_error_reasons/build/missing.txt")
    renamed_path ::= from_literal(.data = "tests/feature_tests/system/26_file_system_error_reasons/build/renamed.txt")

    open_result ::= open_read(.self = system.file_sys, .path = missing_path)
    if is(.value = open_result, .variant = ..error) {
    } else {
        status_code = 1
        return
    }

    if is(.value = open_result..error.reason, .variant = ..path_open_failed) {
    } else {
        status_code = 2
        return
    }

    remove_result ::= remove(.self = system.file_sys, .path = missing_path)
    if is(.value = remove_result, .variant = ..error) {
    } else {
        status_code = 3
        return
    }

    if is(.value = remove_result..error.reason, .variant = ..path_remove_failed) {
    } else {
        status_code = 4
        return
    }

    rename_result ::= rename(.self = system.file_sys, .from = missing_path, .to = renamed_path)
    if is(.value = rename_result, .variant = ..error) {
    } else {
        status_code = 5
        return
    }

    if is(.value = rename_result..error.reason, .variant = ..path_rename_failed) {
    } else {
        status_code = 6
        return
    }

    status_code = 0
}
