invalid(.bytes: [4]UInt8, .count: UIntNative) -> () := {
    text :: StringView = (.data = &bytes[0], .length = count)
    match validate_utf8(.text = text) { ..ok _ { abort } ..error _ {} }
    match utf8_decode(.text = text) { ..ok _ { abort } ..error _ {} }
    decoder ::= Utf8Decoder(.text = text)
    match next_codepoint(.self = $&decoder) { ..ok _ { abort } ..error _ {} }
    if position(.self = &decoder).count != 0 { abort }
}

main() -> !Void = ..ok Void() := {
    invalid(.bytes = (128, 0, 0, 0), .count = 1)
    invalid(.bytes = (191, 0, 0, 0), .count = 1)
    invalid(.bytes = (192, 128, 0, 0), .count = 2)
    invalid(.bytes = (193, 191, 0, 0), .count = 2)
    invalid(.bytes = (194, 0, 0, 0), .count = 1)
    invalid(.bytes = (224, 128, 128, 0), .count = 3)
    invalid(.bytes = (237, 160, 128, 0), .count = 3)
    invalid(.bytes = (237, 191, 191, 0), .count = 3)
    invalid(.bytes = (240, 128, 128, 128), .count = 4)
    invalid(.bytes = (244, 144, 128, 128), .count = 4)
    invalid(.bytes = (245, 128, 128, 128), .count = 4)
    invalid(.bytes = (255, 0, 0, 0), .count = 1)
    invalid(.bytes = (226, 130, 0, 0), .count = 2)
    invalid(.bytes = (226, 65, 172, 0), .count = 3)
    invalid(.bytes = (226, 130, 65, 0), .count = 3)
    match UnicodeScalar(.value = 55296) { ..ok _ { abort } ..error _ {} }
    match UnicodeScalar(.value = 57343) { ..ok _ { abort } ..error _ {} }
    match UnicodeScalar(.value = 1114112) { ..ok _ { abort } ..error _ {} }
    match UnicodeScalar(.value = 4294967295) { ..ok _ { abort } ..error _ {} }
    bytes :: [4]UInt8 = (17, 18, 19, 20)
    scalar ::= UnicodeScalar(.value = 128578)!
    match utf8_encode(.scalar = scalar, .buffer = view(.array = $&bytes), .offset = 1) {
        ..ok _ { abort } ..error _ {}
    }
    if bytes[0] != 17 or bytes[1] != 18 or bytes[2] != 19 or bytes[3] != 20 { abort }
    match utf8_encode(
        .scalar = scalar
        .buffer = view(.array = $&bytes)
        .offset = 18446744073709551615
    ) { ..ok _ { abort } ..error _ {} }
    match utf8_decode(.text = "", .offset = 0) { ..ok _ { abort } ..error _ {} }
    match utf8_decode(.text = "A", .offset = 18446744073709551615) {
        ..ok _ { abort } ..error _ {}
    }
    mixed_bytes :: [2]UInt8 = (65, 255)
    mixed :: StringView = (.data = &mixed_bytes[0], .length = 2)
    decoder ::= Utf8Decoder(.text = mixed)
    next_codepoint(.self = $&decoder)!
    if position(.self = &decoder).count != 1 { abort }
    match next_codepoint(.self = $&decoder) { ..ok _ { abort } ..error _ {} }
    if position(.self = &decoder).count != 1 { abort }
}
