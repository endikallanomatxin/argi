run_main() -> !Void = ..ok Void() := {
    date ::= parse_utc(.text = "2024-02-29T12:34:56.123Z")!
    if date.nanoseconds != 123000000 { abort }
    bytes ::= zeroed#(.t: [30]UInt8)()
    count ::= format_utc_into(.date = date, .buffer = view(.array = $&bytes))!
    if count != 30 { abort }
    text: StringView = (.data = &bytes[0], .length = count)
    if text != "2024-02-29T12:34:56.123000000Z" { abort }
    match parse_utc(.text = "1900-02-29T00:00:00Z") { ..ok _ { abort } ..error _ {} }
    match parse_utc(.text = "2024-02-29T12:34:56.Z") { ..ok _ { abort } ..error _ {} }
    small :: [1]UInt8 = (99)
    match format_utc_into(.date = date, .buffer = view(.array = $&small)) {
        ..ok _ { abort } ..error _ {}
    }
    if small[0] != 99 { abort }
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
