run_main(.system: System) -> !Void = ..ok Void() := {
    date ::= parse_utc(.text = "2024-02-29T12:34:56.123Z")!
    if date.nanoseconds != 123000000 { abort }
    bytes ::= zeroed#(.t: [30]UInt8)()
    count ::= format_utc_into(.date = date, .buffer = view(.self = $&bytes))!
    if count != 30 { abort }
    text_storage ::= unwrap_or_abort(
        .value = string_from_bytes(
            .bytes = unwrap_or_abort(
                .value = slice(&view(&bytes), .start = 0, .count = count)
            )
            .allocator = system.page_allocator
        )
    )
    text ::= view(&text_storage)
    if text != "2024-02-29T12:34:56.123000000Z" { abort }
    match parse_utc(.text = "1900-02-29T00:00:00Z") { ..ok _ { abort } ..error _ {} }
    match parse_utc(.text = "2024-02-29T12:34:56.Z") { ..ok _ { abort } ..error _ {} }
    small :: [1]UInt8 = (99)
    match format_utc_into(.date = date, .buffer = view(.self = $&small)) {
        ..ok _ { abort } ..error _ {}
    }
    if small[0] != 99 { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(
    .system: System, .writer: $&WriterType = reach writer
) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
