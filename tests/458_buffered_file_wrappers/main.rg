main(.system: System = System()) -> (.status_code: Int32) := {
    input_file ::= File(.handle = 0, .should_close = 0 == 1)
    init_stdin_handle(.p = $&input_file)
    input_reader ::= BufferedReader#(.base_type: File)(.allocator = system.allocator, .base = $&input_file, .capacity = 4)

    output_file ::= File(.handle = 0, .should_close = 0 == 1)
    init_stdout_handle(.p = $&output_file)
    output_writer ::= BufferedWriter#(.base_type: File)(.allocator = system.allocator, .base = $&output_file, .capacity = 4)

    if is_open(.self = &input_file).ok {
    } else {
        status_code = 1
        return
    }

    if input_reader.capacity != 4 {
        status_code = 2
        return
    }

    if output_writer.length != 0 {
        status_code = 3
        return
    }

    flush(.self = $&output_writer)
    deinit(.self = $&input_reader, .allocator = system.allocator)
    deinit(.self = $&output_writer, .allocator = system.allocator)
    status_code = 0
}
