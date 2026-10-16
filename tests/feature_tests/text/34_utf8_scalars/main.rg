run_main() -> !Void = ..ok Void() := {
    boundaries :: [11]UInt32 = (
        0,
        127,
        128,
        2047,
        2048,
        55295,
        57344,
        65535,
        65536,
        128578,
        1114111
    )
    encodings :: [11][4]UInt8 = (
        (0, 0, 0, 0),
        (127, 0, 0, 0),
        (194, 128, 0, 0),
        (223, 191, 0, 0),
        (224, 160, 128, 0),
        (237, 159, 191, 0),
        (238, 128, 128, 0),
        (239, 191, 191, 0),
        (240, 144, 128, 128),
        (240, 159, 153, 130),
        (244, 143, 191, 191)
    )
    widths :: [11]UIntNative = (1, 1, 2, 2, 3, 3, 3, 3, 4, 4, 4)
    boundary_index :: UIntNative = 0
    for code in boundaries {
        scalar ::= UnicodeScalar(.value = code)!
        bytes :: [6]UInt8 = (99, 88, 88, 88, 88, 99)
        width ::= utf8_encode(.scalar = scalar, .buffer = view(.self = $&bytes), .offset = 1)!
        if width != widths[boundary_index] { abort }
        byte_index :: UIntNative = 0
        while byte_index < width {
            if bytes[byte_index + 1] != encodings[boundary_index][byte_index] { abort }
            byte_index = byte_index + 1
        }
        while byte_index < 4 {
            if bytes[byte_index + 1] != 88 { abort }
            byte_index = byte_index + 1
        }
        boundary_index = boundary_index + 1
        if width != utf8_encoded_length(.scalar = scalar).count { abort }
        if bytes[0] != 99 or bytes[5] != 99 { abort }
        text ::= unwrap_or_abort(.value = slice(&view(&bytes), .start = 1, .count = width))
        decoded ::= utf8_decode_bytes(.bytes = text)!
        if scalar_value(.self = decoded.scalar).value != code or decoded.width != width {
            abort
        }
        if validate_utf8_bytes(.bytes = text)! != 1 { abort }
    }
    text :: StringView = "Aé€🙂"
    validated :: CodepointView = codepoints(.text = text)
    if length(.self = &validated).count != 4 or byte_length(&text).count != 10 { abort }
    if equals(.left = view(.self = &validated).view, .right = text).ok == false { abort }
    expected :: [4]UInt32 = (65, 233, 8364, 128578)
    index :: UIntNative = 0
    for scalar in validated {
        if scalar_value(.self = scalar).value != expected[index] { abort }
        index = index + 1
    }
    if index != 4 { abort }
    -- Reusing the view starts a new independent decoder.
    again :: UIntNative = 0
    for scalar in validated { again = again + 1 }
    if again != 4 { abort }
    decoder ::= Utf8Decoder(.text = text)
    index = 0
    while index < 4 {
        match next_codepoint(.self = $&decoder)! {
            ..none { abort }
            ..some payload {
                if scalar_value(.self = payload.value).value != expected[index] { abort }
            }
        }
        index = index + 1
    }
    if position(.self = &decoder).count != 10 { abort }
    match next_codepoint(.self = $&decoder)! { ..none {} ..some _ { abort } }
    match next_codepoint(.self = $&decoder)! { ..none {} ..some _ { abort } }
    empty ::= CodepointView(.text = "")
    if length(.self = &empty).count != 0 { abort }
    for scalar in empty { abort }
}

main#(.WriterType: Type: Writer#(WriterType))(.writer: $&WriterType = reach writer) -> (
    .status_code : Int32 = 1
) := {
    run_main()!!!
    status_code = 0
}
