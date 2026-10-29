main := () -> () {
    assume error_tracer ::= $&noop_error_tracer
    bytes: [1]UInt8 = (255)
    text: StringView = (.data = &bytes[0], .length = 1)
    _ ::= bytes_get(.view = &text, .index = 0)
}
