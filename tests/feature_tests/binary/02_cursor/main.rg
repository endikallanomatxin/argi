run_main() -> !Void = ..ok Void() := {
    bytes :: [6]UInt8 = (0, 0, 0, 0, 0, 0)
    writer ::= ByteWriter(.bytes = view(.array = $&bytes))
    write_uint16(.self = $&writer, .value = 4660, .order = ..big)!
    write_uint32(.self = $&writer, .value = 16909060, .order = ..little)!
    if position(.self = &writer).count != 6 or remaining(.self = &writer).count != 0 { abort }
    match write_uint16(.self = $&writer, .value = 0, .order = ..big) {
        ..ok _ { abort } ..error _ {}
    }
    if position(.self = &writer).count != 6 or bytes[0] != 18 { abort }
    reader ::= ByteReader(.bytes = view(.array = &bytes))
    if read_uint16(.self = $&reader, .order = ..big)! != 4660 { abort }
    if read_uint32(.self = $&reader, .order = ..little)! != 16909060 { abort }
    match skip(.self = $&reader, .count = 1) { ..ok _ { abort } ..error _ {} }
    if position(.self = &reader).count != 6 { abort }
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
