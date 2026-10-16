main(.system: System) -> (.status_code: Int32) := {
    assume ffi := system.ffi
    assume writer ::= $&system.terminal&.stdout

    input_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    init_stdin(.p = $&input_file)
    input_storage: [4]UInt8 = (0, 0, 0, 0)
    input_reader ::= BufferedReader#(.base_type: File)(
        .base = $&input_file, .buffer = view($&input_storage)
    )

    output_file ::= File(.stream_address = 0, .should_close = 0 == 1)
    init_stdout(.p = $&output_file)
    output_writer ::= BufferedWriter#(.base_type: File)(
        .base = $&output_file, .buffer = view(.self = $&zeroed#(.t: [4]UInt8)())
    )

    if is_open(.self = &input_file).ok {
    } else {
        status_code = 1
        return
    }

    if length(&input_reader.buffer).count != 4 {
        status_code = 2
        return
    }

    if output_writer.length != 0 {
        status_code = 3
        return
    }

    Writer#().flush(.self = $&output_writer)
    deinit(.self = $&output_writer)
    status_code = 0
}
