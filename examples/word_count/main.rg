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
        )
    ) := {
    result = ..ok Void()
    assume allocator := system.page_allocator
    out ::= $&system.terminal&.stdout
    argc ::= length(.self = system.args).count
    if argc < 2 or argc > 3 {
        write(.self = out, .text = "Usage: word-count <directory> [maximum-file-bytes]\n")!
        return
    }
    limit :: UIntNative = 1048576
    if argc == 3 {
        parsed ::= parse_uintnative(.text = argument_view_at(.self = system.args, .index = 2))!
        limit = parsed
    }
    counts ::= OwnedHashMap#(.key: String, .value: UIntNative, .policy: StringHashPolicy)(
        .policy    = StringHashPolicy()
        .allocator = allocator
    )!
    scratch :: [4]UInt8 = (0, 0, 0, 0)
    words.count_directory(
        .self      = $&counts
        .path      = argument_view_at(.self = system.args, .index = 1)
        .limit     = limit
        .buffer    = view(.array = $&scratch)
        .file_sys  = system.file_sys
        .allocator = allocator
    )!
    for entry in counts {
        write(.self = out, .value = entry.value&)!
        write(.self = out, .text = "\t")!
        write(.self = out, .text = as_view(.self = entry.key))!
        write(.self = out, .text = "\n")!
    }
    flush(.self = out)!
}
