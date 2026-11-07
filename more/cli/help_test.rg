_HelpOutput := (.expected: StringView, .index: UIntNative = 0, .fail: Bool = false)

implement Writer#(_HelpOutput) (
    .write_byte = (.self: $&_HelpOutput, .byte: UInt8) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) {
        if self&.fail {
            result = ..error(.reason = ..stream_write_failed)
            return
        }
        if self&.index >= byte_length(&self&.expected).count { abort }
        expected ::= bytes_get(&self&.expected, .index = self&.index) handle ignored, value {
            abort
        }
        if byte != expected { abort }
        self&.index = self&.index + 1
        result = ..ok Void()
    }

    .flush = (.self: $&_HelpOutput) -> (
        .result : Errable#(Void, (..stream_write_failed, ..stream_flush_failed))
    ) { result = ..ok Void() }
)

test cli_help_text_and_write_errors := () -> !() {
    specs ::= (
        Spec(.name = "help", .short_name = "h", .help = "Show help"),
        Spec(
            .name          = "output"
            .value_name    = "FILE"
            .required      = true
            .repeatable    = true
            .default_value = ..some(.value = "out")
        ),
    )
    expected ::= "Example\nUsage: demo [OPTIONS] [ARGS]\n\nOptions:\n  -h, --help  Show help\n  --output <FILE> (required) (repeatable)   [default: out]\n"
    output ::= _HelpOutput(.expected = expected)
    write_help($&output, .program = "demo", .about = "Example", .specs = view(&specs))!
    if output.index != byte_length(&expected).count { abort }

    failed ::= _HelpOutput(.expected = "", .fail = true)
    match write_help($&failed, .program = "demo", .about = "Example", .specs = view(&specs)) {
        ..ok _ { abort }
        ..error error { if error.reason != ..stream_write_failed { abort } }
    }
}
