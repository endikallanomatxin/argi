words ::= import ("./library")

main(
        .system : System
    ) -> (
        .result : Errable#(
            .t       : Void,
            .reasons : (
                ..invalid_utf8,
                ..out_of_memory,
                ..out_of_range,
                ..invalid_path,
                ..path_not_found,
                ..permission_denied,
                ..already_exists,
                ..not_a_directory,
                ..filesystem_failed,
                ..path_open_failed,
                ..stream_read_failed,
                ..invalid_stream_buffer,
                ..size_limit_exceeded,
                ..size_overflow,
                ..invalid_base,
                ..invalid_input,
                ..stream_write_failed,
                ..stream_flush_failed
            )
        ) = ..ok Void()
    ) := {
    assume allocator := system.page_allocator
    assume writer ::= $&system.terminal&.stdout
    assume file_system := system.file_system

    argc ::= length(system.args).count
    if argc < 2 or argc > 3 {
        write(writer, "Usage: word-count <directory> [maximum-file-bytes]\n")!
        return
    }

    limit :: UIntNative = 1048576
    if argc == 3 {
        limit = parse_uintnative(argument_view_at(system.args, 2))!
    }

    counts ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        .policy = StringHashPolicy()
    )!
    scratch ::= zeroed#([4]UInt8)()
    words.count_directory(
        .self   = $&counts
        .path   = argument_view_at(system.args, 1)
        .limit  = limit
        .buffer = view($&scratch)
    )!

    for entry in counts {
        write(writer, .value = entry.value&)!
        write(writer, "\t")!
        write(writer, as_view(entry.key))!
        write(writer, "\n")!
    }

    flush()!
}
