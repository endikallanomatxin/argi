http := import ("network/http")

escape := () -> (.head: http.RequestHead) {
    input: StringView = "GET / HTTP/1.1\r\nHost: example\r\n\r\n"
    reader ::= ByteReader(.bytes = string_bytes(.text = input))
    storage :: [128]UInt8 = zeroed#([128]UInt8)()
    head = unwrap_or_abort(
        .value = http.read_request(.reader = $&reader, .buffer = view($&storage))
    )
}

main := () -> (.status_code: Int32 = 0) {
    head ::= escape()
    if head.header_count != 1 { abort }
}
