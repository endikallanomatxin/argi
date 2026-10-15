main(.system: System) -> () := {
    assume allocator := system.page_allocator
    bytes: [5]UInt8 = (240, 159, 152, 128, 10)
    reader ::= ByteReader(.bytes = view(&bytes))
    text ::= unwrap_or_abort(.value = string_with_capacity(.capacity = 8))
    unwrap_or_abort(
        .value = read_line_into_buffer(
            .buffer = $&text, .allocator = allocator, .reader = $&reader
        )
    )
    if as_view(&text) != "😀" { abort }
    malformed: [3]UInt8 = (192, 128, 10)
    invalid ::= ByteReader(.bytes = view(&malformed))
    match read_line_into_buffer(.buffer = $&text, .allocator = allocator, .reader = $&invalid) {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    if byte_length(&text) != 0 { abort }
    bounded ::= unwrap_or_abort(.value = string_with_capacity(.capacity = 1))
    truncated ::= ByteReader(.bytes = view(&bytes))
    match read_line_into_buffer(
        .buffer = $&bounded, .allocator = allocator, .reader = $&truncated
    ) {
        ..ok _ { abort }
        ..error failure { if failure.reason != ..invalid_utf8 { abort } }
    }
    if byte_length(&bounded) != 0 { abort }
}
