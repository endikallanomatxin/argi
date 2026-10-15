main() -> () := {
    bytes: [1]UInt8 = (255)
    text: StringView = (&bytes[0], 1)
    _ ::= bytes_get(.view = &text, .index = 0)
}
