Refusing: Type = (.attempts: UIntNative = 0)

implement Allocator#(Refusing) (
    .allocate = (.self: $&Refusing, .size: UIntNative, .alignment: UIntNative = 1) -> (
        .result : Errable#(Allocation, (..out_of_memory))
    ) {
        self&.attempts = self&.attempts + 1
        result = ..error(.reason = ..out_of_memory)
    }
)

main(.system: System) -> () := {
    assume allocator := system.page_allocator
    text ::= unwrap_or_abort(.value = format(.value = "Aé"))
    before ::= capacity(&text).count
    refusing ::= Refusing()
    byte :: UIntNative = 128
    while byte < 256 {
        invalid ::= unwrap_or_abort(.value = byte | convert#(.to: UInt8)(_))
        match push_ascii($&text, .byte = invalid, .allocator = $&refusing) {
            ..ok _ { abort }
            ..error error { if error.reason != ..invalid_ascii { abort } }
        }
        match append_ascii_assume_capacity($&text, .byte = invalid) {
            ..ok _ { abort }
            ..error error { if error.reason != ..invalid_ascii { abort } }
        }
        match set_ascii($&text, .index = 0, .byte = invalid) {
            ..ok _ { abort }
            ..error error { if error.reason != ..invalid_ascii { abort } }
        }
        if view(&text) != "Aé" or capacity(&text).count != before { abort }
        byte = byte + 1
    }
    if refusing.attempts != 0 { abort }
    match set_ascii($&text, .index = 1, .byte = 65) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_ascii { abort } }
    }
    match set_ascii($&text, .index = 2, .byte = 65) {
        ..ok _ { abort }
        ..error error { if error.reason != ..invalid_ascii { abort } }
    }
    match set_ascii($&text, .index = 3, .byte = 65) {
        ..ok _ { abort }
        ..error error { if error.reason != ..out_of_bounds { abort } }
    }
    if view(&text) != "Aé" { abort }
    unwrap_or_abort(.value = push_ascii($&text, .byte = 127))
    unwrap_or_abort(.value = push_ascii($&text, .byte = 0))
    if byte_length(&text).count != 5 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &text, .index = 3)) != 127 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &text, .index = 4)) != 0 { abort }
}
