main(.system: System = System()) -> (.status_code: Int32) := {
    input_file ::= File(.descriptor = 0, .kind = ..stdin)
    input_reader ::= FileReader(.file = $&input_file)
    buffered_reader ::= BufferedReader(.reader = $&input_reader, .capacity = 4)

    output_file ::= File(.descriptor = 1, .kind = ..stdout)
    output_writer ::= FileWriter(.file = $&output_file)
    buffered_writer ::= BufferedWriter(.writer = $&output_writer, .capacity = 4)

    if buffered_reader.capacity != 4 {
        status_code = 1
        return
    }

    if buffered_writer.length != 0 {
        status_code = 2
        return
    }

    deinit(.self = $&buffered_reader, .allocator = system.allocator)
    deinit(.self = $&buffered_writer, .allocator = system.allocator)
    status_code = 0
}
