main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator

    path ::= from_literal(.data = "tests/feature_tests/system/34_file_block_short_read_temp.bin")

    if exists(.self = system.file_sys, .path = path).ok {
        removed ::= remove(.self = system.file_sys, .path = path)
        if is(.value = removed, .variant = ..ok) {
        } else {
            status_code = 1
            return
        }
    }

    create_result ::= open_write(.self = system.file_sys, .path = path)
    if is(.value = create_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    file ::= ~create_result..ok

    write_bytes : Array#(.n = 2, .t: UInt8) = (0, 0)
    write_buffer ::= array_view(.array = $&write_bytes)
    first_set ::= set#(.t: UInt8)(.self = $&write_buffer, .index = 0, .value = 41).result
    second_set ::= set#(.t: UInt8)(.self = $&write_buffer, .index = 1, .value = 42).result
    if is(.value = first_set, .variant = ..error) or is(.value = second_set, .variant = ..error) {
        close(.self = $&file)
        status_code = 4
        return
    }

    write_result ::= write(.self = $&file, .buffer = write_buffer)

    if is(.value = write_result, .variant = ..ok) {
    } else {
        close(.self = $&file)
        status_code = 4
        return
    }

    if write_result..ok != 2 {
        close(.self = $&file)
        status_code = 5
        return
    }

    close(.self = $&file)

    open_result ::= open_read(.self = system.file_sys, .path = path)
    if is(.value = open_result, .variant = ..ok) {
    } else {
        status_code = 6
        return
    }
    file = ~open_result..ok

    read_bytes : Array#(.n = 4, .t: UInt8) = (0, 0, 0, 0)
    read_buffer ::= array_view(.array = $&read_bytes)

    read_result ::= read(.self = $&file, .buffer = read_buffer)
    close(.self = $&file)

    if is(.value = read_result, .variant = ..ok) {
    } else {
        status_code = 8
        return
    }

    count ::= read_result..ok
    if count != 2 {
        status_code = 9
        return
    }

    first_read ::= get#(.t: UInt8)(.self = &read_buffer, .index = 0).result
    if is(.value = first_read, .variant = ..error) {
        status_code = 10
        return
    }
    if first_read..ok != 41 {
        status_code = 10
        return
    }

    second_read ::= get#(.t: UInt8)(.self = &read_buffer, .index = 1).result
    if is(.value = second_read, .variant = ..error) {
        status_code = 11
        return
    }
    if second_read..ok != 42 {
        status_code = 11
        return
    }

    removed ::= remove(.self = system.file_sys, .path = path)
    if is(.value = removed, .variant = ..ok) {
        status_code = 0
    } else {
        status_code = 12
    }
}
