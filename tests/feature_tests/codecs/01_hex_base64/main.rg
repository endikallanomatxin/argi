hex := import ("codecs/encoding/hex")
base64 := import ("codecs/encoding/base64")

main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    bytes :: [3]UInt8 = (102, 111, 111)
    text ::= hex.encode(.bytes = view(.array = &bytes), .allocator = allocator)!
    if as_view(.self = &text) != "666f6f" { abort }
    decoded ::= hex.decode(.text = "666F6f", .allocator = allocator)!
    if length(.self = &decoded).count != 3 { abort }
    encoded ::= base64.encode(.bytes = view(.array = &bytes), .allocator = allocator)!
    if as_view(.self = &encoded) != "Zm9v" { abort }
    roundtrip ::= base64.decode(.text = "Zg==", .allocator = allocator)!
    if [
        length(.self = &roundtrip).count != 1
        or unwrap_or_abort(.value = get(.self = &roundtrip, .index = 0)) != 102
    ] { abort }
    match base64.decode(.text = "Zh==", .allocator = allocator) { ..ok ~_ { abort } ..error _ {} }
    match base64.decode(.text = "Z=g=", .allocator = allocator) { ..ok ~_ { abort } ..error _ {} }
    match hex.decode(.text = "0g", .allocator = allocator) { ..ok ~_ { abort } ..error _ {} }
    high :: [3]UInt8 = (0, 255, 128)
    high_text ::= base64.encode(.bytes = view(.array = &high), .allocator = allocator)!
    if as_view(.self = &high_text) != "AP+A" { abort }
    scratch ::= zeroed#(.t: [32]UInt8)()
    index :: UIntNative = 0
    while index < 32 {
        scratch[index] = unwrap_or_abort(.value = UInt8(.value = [index * 29 + index % 5] % 256))
        index = index + 1
    }
    all_bytes ::= view(.array = &scratch)
    count :: UIntNative = 0
    while count <= 32 {
        input ::= unwrap_or_abort(
            .value = slice(.self = &all_bytes, .start = 0, .count = count)
        )
        encoded ::= base64.encode(.bytes = input, .allocator = allocator)!
        decoded ::= base64.decode(.text = as_view(.self = &encoded), .allocator = allocator)!
        hexed ::= hex.encode(.bytes = input, .allocator = allocator)!
        unhexed ::= hex.decode(.text = as_view(.self = &hexed), .allocator = allocator)!
        if length(.self = &decoded).count != count or length(.self = &unhexed).count != count {
            abort
        }
        index = 0
        while index < count {
            if unwrap_or_abort(.value = get(.self = &decoded, .index = index)) != scratch[index] {
                abort
            }
            if unwrap_or_abort(.value = get(.self = &unhexed, .index = index)) != scratch[index] {
                abort
            }
            index = index + 1
        }
        count = count + 1
    }
    invalid :: [9]StringView = (
        "A",
        "AA",
        "AAAA=",
        "A===",
        "=AAA",
        "AA=A",
        "AA==\n",
        "___=",
        "AB=="
    )
    for text in invalid {
        match base64.decode(.text = text, .allocator = allocator) {
            ..ok ~_ { abort } ..error _ {}
        }
    }
}
