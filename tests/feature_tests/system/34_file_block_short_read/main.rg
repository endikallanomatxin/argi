main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    path ::= from_literal(
        .data = "tests/feature_tests/system/34_file_block_short_read/build/temp.bin"
    )

    if exists(.self = system.file_system, .path = path).ok {
        removed ::= remove(.self = system.file_system, .path = path)
        if is(.value = removed, .variant = ..ok) {
        } else {
            status_code = 1
            return
        }
    }

    create_result ::= open_file(
        .file_system = system.file_system, .path = path, .mode = ..write
    )
    if is(.value = create_result, .variant = ..ok) {
    } else {
        status_code = 2
        return
    }
    file ::= ~create_result ..ok

    write_bytes: Array#(.n = 2, .t: UInt8) = (0, 0)
    write_buffer ::= view(.self = $&write_bytes)
    first_set ::= set#(.t: UInt8)(.self = $&write_buffer, .index = 0, .value = 41).result
    second_set ::= set#(.t: UInt8)(.self = $&write_buffer, .index = 1, .value = 42).result
    if is(.value = first_set, .variant = ..error) or is(.value = second_set, .variant = ..error) {
        close(.self = $&file)
        status_code = 4
        return
    }

    write_result ::= write(.self = $&file, .value = write_buffer)

    if is(.value = write_result, .variant = ..ok) {
    } else {
        close(.self = $&file)
        status_code = 4
        return
    }

    if write_result ..ok != 2 {
        close(.self = $&file)
        status_code = 5
        return
    }

    -- A native write-only stream reports read failures through both protocols.
    denied_read: [1]UInt8 = (99)
    match read(.self = $&file, .buffer = view($&denied_read)) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    match Reader#().read_byte(.self = $&file) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_read_failed { abort } }
    }
    {
        buffered ::= BufferedReader(.base = $&file, .buffer = view($&denied_read))
        match Reader#().read_byte(.self = $&buffered) {
            ..ok _ { abort }
            ..error error { if error.reason != ..stream_read_failed { abort } }
        }
    }
    if denied_read[0] != 99 { abort }

    close(.self = $&file)

    open_result ::= open_file(.file_system = system.file_system, .path = path, .mode = ..read)
    if is(.value = open_result, .variant = ..ok) {
    } else {
        status_code = 6
        return
    }
    file = ~open_result ..ok

    read_bytes: Array#(.n = 4, .t: UInt8) = (0, 0, 0, 0)
    read_buffer ::= view(.self = $&read_bytes)

    read_result ::= read(.self = $&file, .buffer = read_buffer)
    close(.self = $&file)

    if is(.value = read_result, .variant = ..ok) {
    } else {
        status_code = 8
        return
    }

    count ::= read_result ..ok
    if count != 2 {
        status_code = 9
        return
    }

    first_read ::= get(.self = &read_buffer, .index = 0).result
    if is(.value = first_read, .variant = ..error) {
        status_code = 10
        return
    }
    if first_read ..ok != 41 {
        status_code = 10
        return
    }

    second_read ::= get(.self = &read_buffer, .index = 1).result
    if is(.value = second_read, .variant = ..error) {
        status_code = 11
        return
    }
    if second_read ..ok != 42 {
        status_code = 11
        return
    }

    -- Closing and reopening separates each native stream's sticky error state.
    denied_writer ::= unwrap_or_abort(
        .value = open_file(.file_system = system.file_system, .path = path, .mode = ..read)
    )
    match write(.self = $&denied_writer, .value = write_buffer) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    match BlockWriter#().write_block(.self = $&denied_writer, .buffer = view(&write_bytes)) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    match Writer#().write_byte(.self = $&denied_writer, .byte = 99) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
    {
        storage: [1]UInt8 = (0)
        buffered ::= BufferedWriter(.base = $&denied_writer, .buffer = view($&storage))
        match Writer#().write_byte(.self = $&buffered, .byte = 99) {
            ..ok _ { abort }
            ..error error { if error.reason != ..stream_write_failed { abort } }
        }
        if buffered.length != 0 { abort }
    }
    unwrap_or_abort(.value = close(.self = $&denied_writer))

    removed ::= remove(.self = system.file_system, .path = path)
    if is(.value = removed, .variant = ..ok) {
        status_code = 0
    } else {
        status_code = 12
    }
}
