failed_stream() -> (.address: UIntNative): CFunction(.symbol = "argi_test_failed_file")

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
}
