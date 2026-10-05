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
}
