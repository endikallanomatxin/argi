write_help := #(.WriterType: Type: Writer#(WriterType)) (
    .writer  : $&WriterType,
    .program : StringView,
    .about   : StringView,
    .specs   : ArrayView#(.t: Spec)
) -> (.result: Errable#(Void, (..stream_write_failed, ..stream_flush_failed)) = ..ok Void()) {

    write(writer, .value = about)!
    write(writer, .value = "\nUsage: ")!
    write(writer, .value = program)!
    write(writer, .value = " [OPTIONS] [ARGS]\n\nOptions:\n")!
    _write_options(writer, specs)!
}

_write_options := #(.W: Type: Writer#(W)) (.writer: $&W, .specs: ArrayView#(Spec)) -> !() {
    index :: UIntNative = 0

    while index < length(&specs).count {
        spec ::= get(&specs, .index = index) handle ignored, value { abort }
        write(writer, .value = "  ")!
        if byte_length(&spec.short_name).count > 0 {
            write(writer, .value = "-")!
            write(writer, .value = spec.short_name)!
            write(writer, .value = ", ")!
        }
        write(writer, .value = "--")!
        write(writer, .value = spec.name)!
        if byte_length(&spec.value_name).count > 0 {
            write(writer, .value = " <")!
            write(writer, .value = spec.value_name)!
            write(writer, .value = ">")!
        }
        if spec.required { write(writer, .value = " (required)")! }
        if spec.repeatable { write(writer, .value = " (repeatable)")! }
        write(writer, .value = "  ")!
        write(writer, .value = spec.help)!
        match spec.default_value {
            ..none {} ..some entry {
                write(writer, .value = " [default: ")!
                write(writer, .value = entry.value)!
                write(writer, .value = "]")!
            }
        }
        write(writer, .value = "\n")!
        index = index + 1
    }
}

write_command_help := #(.W: Type: Writer#(W)) (
    .writer   : $&W,
    .program  : StringView,
    .about    : StringView           = "",
    .commands : ArrayView#(Command),
    .command  : StringView           = ""
) -> !() {
    if byte_length(&command) == 0 {
        write(writer, about)!
        write(writer, "\nUsage: ")!
        write(writer, program)!
        write(writer, " <COMMAND> [OPTIONS] [ARGS]\n\nCommands:\n")!
        for entry in commands {
            write(writer, "  ")!
            write(writer, entry.name)!
            write(writer, "  ")!
            write(writer, entry.about)!
            write(writer, "\n")!
        }
    } else {
        for entry in commands {
            if entry.name == command {
                write(writer, entry.about)!
                write(writer, "\nUsage: ")!
                write(writer, program)!
                write(writer, " ")!
                write(writer, entry.name)!
                write(writer, " [OPTIONS] [ARGS]\n\nOptions:\n")!
                _write_options(writer, entry.specs)!
                write(writer, "  -h, --help  Show help\n")!
                return
            }
        }
        write(writer, "Unknown command: ")!
        write(writer, command)!
        write(writer, "\n")!
        return
    }
    write(writer, "\nUse <COMMAND> --help for command help.\n  -h, --help  Show help\n")!
}
