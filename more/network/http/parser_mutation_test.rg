test http_parser_mutations := () -> !() {
    text: StringView = "POST /path HTTP/1.1\r\nHost: example\r\nX-Name: value\r\nContent-Length: 3\r\n\r\n"
    original ::= string_bytes(.text = text)
    count ::= length(&original).count
    data :: [128]UInt8 = zeroed#([128]UInt8)()
    i :: UIntNative = 0
    while i < count {
        data[i] = unwrap_or_abort(.value = get(&original, .index = i))
        i = i + 1
    }
    i = 0
    while i < count {
        bytes ::= view(&data)
        prefix ::= unwrap_or_abort(.value = slice(&bytes, .start = 0, .count = i))
        match parse_request(.bytes = prefix) {
            ..ok _ { abort }
            ..error _ {}
        }
        i = i + 1
    }
    mutations: [5]UInt8 = (0, 10, 13, 58, 255)
    i = 0
    while i < count {
        saved ::= data[i]
        j :: UIntNative = 0
        while j < 5 {
            data[i] = mutations[j]
            bytes ::= view(&data)
            candidate ::= unwrap_or_abort(.value = slice(&bytes, .start = 0, .count = count))
            match parse_request(.bytes = candidate) { ..ok _ {} ..error _ {} }
            j = j + 1
        }
        data[i] = saved
        i = i + 1
    }
    binary :: [35]UInt8 = (
        71, 69, 84, 32, 47, 32, 72, 84, 84, 80, 47, 49, 46, 49, 13, 10, 72, 111, 115, 116, 58,
        32, 120, 13, 10, 88, 58, 32, 255, 13, 10, 13, 10, 0, 0
    )
    all ::= view(&binary)
    head_bytes ::= unwrap_or_abort(.value = slice(&all, .start = 0, .count = 33))
    head ::= unwrap_or_abort(.value = parse_request(.bytes = head_bytes))
    match header(.self = &head, .name = "x").value {
        ..none { abort }
        ..some item {
            testing.expect(
                [[unwrap_or_abort(.value = get(&item.value.value, .index = 0)) != 255] == false]
            )!
        }
    }
    native_zero: UIntNative = 0
    huge: StringView = "POST / HTTP/1.1\r\nHost: x\r\nContent-Length: 18446744073709551616\r\n\r\n"
    match parse_request(
        .bytes  = string_bytes(.text = huge)
        .limits = Limits(.max_body_bytes = integer_limits(.value = native_zero).maximum)
    ) {
        ..ok _ { abort }
        ..error error { testing.expect([error.reason != ..body_too_large] == false)! }
    }
}
