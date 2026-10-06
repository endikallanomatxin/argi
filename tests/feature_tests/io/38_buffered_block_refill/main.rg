Source: Type = (.count: UIntNative)

Source implements Reader

read_byte(.self: $&Source) -> (.result: Errable#(.t: ReadByte, .reasons: (..stream_read_failed))) := {
    if self&.count == 4 {
        result = ..ok ..end
        return
    }
    self&.count = self&.count + 1
    result = ..ok ..ok 65
}

run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    source :: Source = (.count = 0)
    reader ::= BufferedReader(.base = $&source, .allocator = allocator, .capacity = 3)!
    match read_byte(.self = $&reader)! { ..end { abort } ..ok byte { if byte != 65 { abort } } }
    if source.count != 3 { abort }
    match read_byte(.self = $&reader)! { ..end { abort } ..ok byte {} }
    if source.count != 3 { abort }
    bytes :: [2]UInt8 = (0, 0)
    read_exact(.self = $&reader, .buffer = view(.array = $&bytes))!
    if source.count != 4 or bytes[0] != 65 or bytes[1] != 65 { abort }
    match read_byte(.self = $&reader)! { ..end {} ..ok byte { abort } }
}

main(.system: System, .writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main(.system = system)!!!
    status_code = 0
}
