main(.system: System = System()) -> (.status_code: Int32) := {
    path ::= from_literal(.data = "tests/usecase_tests/05_file_system_read_write/build/temp.txt")

    if exists(.self = system.file_sys, .path = path).ok {
        if remove(.self = system.file_sys, .path = path).ok {
        } else {
            status_code = 1
            return
        }
    }

    text ::= String(.allocator = system.allocator, .length = 4)
    bytes_set(.string = $&text, .index = 0, .value = 65)
    bytes_set(.string = $&text, .index = 1, .value = 114)
    bytes_set(.string = $&text, .index = 2, .value = 103)
    bytes_set(.string = $&text, .index = 3, .value = 105)

    if write_file(.self = system.file_sys, .path = path, .text = text).ok {
    } else {
        status_code = 2
        return
    }

    read_back ::= read_file(.self = system.file_sys, .path = path)

    if read_back.length != 4 {
        status_code = 3
        return
    }

    if bytes_get(.string = &read_back, .index = 0).byte != 65 {
        status_code = 4
        return
    }

    if bytes_get(.string = &read_back, .index = 1).byte != 114 {
        status_code = 5
        return
    }

    if bytes_get(.string = &read_back, .index = 2).byte != 103 {
        status_code = 6
        return
    }

    if bytes_get(.string = &read_back, .index = 3).byte != 105 {
        status_code = 7
        return
    }

    if remove(.self = system.file_sys, .path = path).ok {
    } else {
        status_code = 8
        return
    }

    deinit(.self = $&read_back)
    deinit(.self = $&text)
    status_code = 0
}
