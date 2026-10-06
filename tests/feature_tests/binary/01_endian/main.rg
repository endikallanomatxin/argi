run_main() -> !Void = ..ok Void() := {
    bytes :: [10]UInt8 = (99, 0, 0, 0, 0, 0, 0, 0, 0, 88)
    output ::= view(.array = $&bytes)
    write_uint64(.bytes = output, .offset = 1, .value = 18446744073709551615, .order = ..big)!
    if bytes[0] != 99 or bytes[9] != 88 { abort }
    if [
        read_uint64(.bytes = view(.array = &bytes), .offset = 1, .order = ..little)!
        != 18446744073709551615
    ] { abort }
    write_uint32(.bytes = output, .offset = 1, .value = 16909060, .order = ..big)!
    if bytes[1] != 1 or bytes[2] != 2 or bytes[3] != 3 or bytes[4] != 4 { abort }
    if read_uint32(.bytes = view(.array = &bytes), .offset = 1, .order = ..little)! != 67305985 {
        abort
    }
    write_uint16(.bytes = output, .offset = 7, .value = 4660, .order = ..little)!
    if bytes[7] != 52 or bytes[8] != 18 { abort }
    match write_uint32(.bytes = output, .offset = 8, .value = 0, .order = ..big) {
        ..ok _ { abort } ..error _ {}
    }
    if bytes[8] != 18 or bytes[9] != 88 { abort }
    match read_uint64(
        .bytes  = view(.array = &bytes)
        .offset = 18446744073709551615
        .order  = ..big
    ) {
        ..ok _ { abort } ..error _ {}
    }
}

main(.writer: $&Writer = reach writer) -> (.status_code: Int32 = 1) := {
    run_main()!!!
    status_code = 0
}
