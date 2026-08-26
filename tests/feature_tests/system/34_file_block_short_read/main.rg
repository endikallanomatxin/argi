main(.system: System = System()) -> (.status_code: Int32) := {
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
    file ::= create_result..ok

    write_allocation ::= allocate(.self = system.allocator, .size = 2)

    write_buffer ::= array_view#(.t: UInt8)(
        .data = write_allocation.data,
        .length = 2,
    )
    write_buffer[0] = 41
    write_buffer[1] = 42

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
    file = open_result..ok

    read_allocation ::= allocate(.self = system.allocator, .size = 4)

    read_buffer ::= array_view#(.t: UInt8)(
        .data = read_allocation.data,
        .length = 4,
    )

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

    if read_buffer[0] != 41 {
        status_code = 10
        return
    }

    if read_buffer[1] != 42 {
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
