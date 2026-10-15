run_main(.system: System) -> !Void = ..ok Void() := {
    assume allocator ::= system.page_allocator
    assume error_tracer ::= $&noop_error_tracer
    bytes: [4]UInt8 = (240, 159, 152, 128)
    source ::= view(&bytes)
    text ::= string_from_bytes(.bytes = source)!
    borrowed ::= as_view(&text)
    if byte_length(&borrowed) != 4 { abort }
    if utf8_decode(.text = borrowed)!.width != 4 { abort }
    match slice(.self = borrowed, .start = 1, .count = 1) {
        ..ok _ { abort }
        ..error _ {}
    }
    bytes[0] = 255
    if bytes_get(.view = &borrowed, .index = 0).byte != 240 { abort }
    scalar ::= UnicodeScalar(.value = 233)!
    push_scalar($&text, .scalar = scalar)!
    if byte_length(&text) != 6 { abort }
    invalid: [2]UInt8 = (192, 128)
    match string_from_bytes(.bytes = view(&invalid)) {
        ..ok ~value { abort }
        ..error _ {}
    }
}

main(.system: System) -> () := {
    match run_main(system) { ..ok _ {} ..error _ { abort } }
}
