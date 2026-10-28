failed_stream() -> (.address: UIntNative): CFunction(.symbol = "argi_test_failed_file")

interrupted_input() -> (.address: UIntNative): CFunction(
    .symbol = "argi_test_interrupted_input"
)

interrupted_reads() -> (.count: UIntNative): CFunction(.symbol = "argi_test_interrupted_reads")

interrupted_closes() -> (.count: UIntNative): CFunction(
    .symbol = "argi_test_interrupted_closes"
)

main := (.system: System) -> () {
    assume ffi := system.ffi
    first ::= failed_stream().address
    if first == 0 { abort }
    file ::= file_from_stream(.stream_address = first, .should_close = true)
    match Writer#().flush(.self = $&file) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_flush_failed { abort } }
    }
    if is_open(.self = &file).ok == false { abort }
    match close(.self = $&file) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_close_failed { abort } }
    }
    if is_open(.self = &file).ok { abort }
    -- fclose has released its FILE even on failure; neither retry nor cleanup
    -- may call it again through the stale address.
    unwrap_or_abort(.value = close(.self = $&file))

    second ::= failed_stream().address
    if second == 0 { abort }
    buffered_file ::= file_from_stream(.stream_address = second, .should_close = true)
    {
        storage: [1]UInt8 = (0)
        buffered ::= BufferedWriter(.base = $&buffered_file, .buffer = view($&storage))
        match Writer#().write_byte(.self = $&buffered, .byte = 66) {
            ..ok _ { abort }
            ..error error { if error.reason != ..stream_flush_failed { abort } }
        }
        if buffered.length != 0 { abort }
    }
    match close(.self = $&buffered_file) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_close_failed { abort } }
    }
    if is_open(.self = &buffered_file).ok { abort }

    mode :: UIntNative = 0
    while mode < 3 {
        address ::= interrupted_input().address
        if address == 0 { abort }
        input ::= file_from_stream(.stream_address = address, .should_close = true)
        bytes: [2]UInt8 = (99, 99)
        if mode == 0 {
            match Reader#().read_byte(.self = $&input) {
                ..ok _ { abort }
                ..error error { if error.reason != ..stream_read_failed { abort } }
            }
        } else if mode == 1 {
            match read(.self = $&input, .buffer = view($&bytes)) {
                ..ok _ { abort }
                ..error error { if error.reason != ..stream_read_failed { abort } }
            }
        } else {
            reader ::= BufferedReader(.base = $&input, .buffer = view($&bytes))
            match Reader#().read_byte(.self = $&reader) {
                ..ok _ { abort }
                ..error error { if error.reason != ..stream_read_failed { abort } }
            }
        }
        if bytes[0] != 99 or bytes[1] != 99 { abort }
        if interrupted_reads().count == 0 or interrupted_closes().count != 0 { abort }
        unwrap_or_abort(.value = close(.self = $&input))
        unwrap_or_abort(.value = close(.self = $&input))
        if interrupted_closes().count != 1 { abort }
        mode = mode + 1
    }
}
