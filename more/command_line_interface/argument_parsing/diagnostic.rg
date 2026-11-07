-- Optional borrowed context for a failed parse. The source and schema must
-- remain alive while a caller displays this value.
Diagnostic := (
    .argument : StringView = "",
    .value    : StringView = "",
    .message  : StringView = ""
)

_set_diagnostic := (
    .target: ?$&Diagnostic, .argument: StringView, .value: StringView = "", .message: StringView
) -> () {
    match target {
        ..none {}
        ..some entry {
            entry.value&= (.argument = argument, .value = value, .message = message)
        }
    }
}

write_diagnostic := #(.W: Type: Writer#(W)) (.writer: $&W, .diagnostic: &Diagnostic) -> !() {
    write(writer, "error: ")!
    write(writer, diagnostic&.message)!
    if byte_length(&diagnostic&.argument) > 0 {
        write(writer, " '")!
        write(writer, diagnostic&.argument)!
        write(writer, "'")!
    }
    if byte_length(&diagnostic&.value) > 0 {
        write(writer, ": '")!
        write(writer, diagnostic&.value)!
        write(writer, "'")!
    }
    write(writer, "\n")!
}
