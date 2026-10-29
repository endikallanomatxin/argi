forward := (.text: StringView) -> (.view: StringView) {
    view = trim(.self = text).view
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    if trim(.self = "").view != "" { abort }
    if trim(.self = " \t\r\n ").view != "" { abort }
    if trim(.self = "hello").view != "hello" { abort }
    if trim(.self = " \t hello \r\n").view != "hello" { abort }
    if trim_start(.self = "  hello  ").view != "hello  " { abort }
    if trim_end(.self = "  hello  ").view != "  hello" { abort }
    if trim(.self = " a b ").view != "a b" { abort }
    if trim(.self = " x ").view != " x " { abort }
    bytes: [8]UInt8 = (9, 10, 11, 12, 13, 32, 120, 32)
    all: StringView = "\t\n\r x "
    trimmed ::= forward(.text = all).view
    if trimmed != "x" { abort }
    if [
        byte_data(.text = trimmed).reference | convert#(.to: UIntNative)(_)
        != [byte_data(.text = all).reference | convert#(.to: UIntNative)(_) + 6]
    ] { abort }
    binary: [3]UInt8 = (32, 0, 32)
    zeros: StringView = " \0 "
    zero ::= trim(.self = zeros).view
    if byte_length(&zero).count != 1 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &zero, .index = 0)) != 0 { abort }
}
