json ::= import ("codecs/serialization/json")

main(.system: System) -> !Void = ..ok Void() := {
    json.validate(
        .text = " {\"text\":\"café \\uD83D\\uDE42\", \"values\":[null,true,false,-1.2e+3]} "
    )!
    cases :: [12]StringView = (
        "",
        "01",
        "1.",
        "1e+",
        "[1,]",
        "{\"a\" 1}",
        "true false",
        "\"\\uDC00\"",
        "\"\\uD800x\"",
        "\"\\x\"",
        "[}",
        "{\"a\":1,}"
    )
    for text in cases {
        match json.validate(.text = text) {
            ..ok _ { abort } ..error error { if [
                    error.reason
                    != ..invalid_json
                ] { abort } }
        }
    }
    match json.validate(.text = "[[]]", .maximum_depth = 1) {
        ..ok _ { abort } ..error error { if [
                error.reason
                != ..json_depth_exceeded
            ] { abort } }
    }
    cursor ::= json.JsonCursor(.text = "[1,true,\"x\"]")!
    count :: UIntNative = 0
    while true {
        match json.next(.self = $&cursor)! {
            ..none { break } ..some token {
                if [
                    token.value.lexeme.length
                    == 0
                ] { abort }
                count = [
                    count
                    + 1
                ]
            }
        }
    }
    if count != 7 { abort }
    match json.next(.self = $&cursor)! { ..none {} ..some _ { abort } }
    assume allocator := system.page_allocator
    decoded ::= json.decode_string(
        .text      = "\"caf\\u00e9 \\uD83D\\uDE42\\n\""
        .allocator = allocator
    )!
    if as_view(.self = &decoded) != "café 🙂\n" { abort }
    storage ::= zeroed#(.t: [64]UInt8)()
    writer ::= ByteWriter(.bytes = view(.array = $&storage))
    json.write_string(.writer = $&writer, .text = as_view(.self = &decoded))!
    text :: StringView = (.data = &storage[0], .length = 18)
    json.validate(.text = text)!
}
