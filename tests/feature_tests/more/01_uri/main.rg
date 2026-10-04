uri := import ("network/uri")
roundtrip(.text: StringView, .allocator: $&Allocator) -> () := {
    parsed ::= unwrap_or_abort(.value = uri.parse(.text = text)).result
    rendered ::= unwrap_or_abort(.value = uri.build(.value = parsed, .allocator = allocator)).result
    if as_view(.self = &rendered).view != text { abort }
}
main(.system: System) -> (.status_code: Int32 = 0) := {
    roundtrip(.text = "https://user@example.com:443/a%2Fb?x=1#frag",
        .allocator = system.page_allocator)
    roundtrip(.text = "../file?", .allocator = system.page_allocator)
    roundtrip(.text = "//[::1]:80/", .allocator = system.page_allocator)
    roundtrip(.text = "//[::ffff:192.0.2.1]/", .allocator = system.page_allocator)
    roundtrip(.text = "//[v1.future:host]/", .allocator = system.page_allocator)
    roundtrip(.text = "mailto:user@example.com", .allocator = system.page_allocator)
    roundtrip(.text = "?#", .allocator = system.page_allocator)
    roundtrip(.text = "", .allocator = system.page_allocator)
    encoded ::= unwrap_or_abort(.value = uri.encode_component(.text = "a b/+é",
            .allocator = system.page_allocator)).result
    if as_view(.self = &encoded).view != "a%20b%2F%2B%C3%A9" { abort }
    decoded ::= unwrap_or_abort(.value = uri.decode_component(.text = as_view(.self = &encoded).view,

            .allocator = system.page_allocator)).result
    if as_view(.self = &decoded).view != "a b/+é" { abort }
    parts ::= unwrap_or_abort(.value = uri.authority_parts(.text = "user@[::1]:443")).result
    if parts.host != "[::1]" { abort }
    match parts.port { ..some item { if item.value != "443" { abort } } ..none { abort } }
    invalid_value: uri.UriView = (.scheme = ..none, .authority = ..none,
        .path = "a:b", .query = ..none, .fragment = ..none)
    match uri.build(.value = invalid_value, .allocator = system.page_allocator) {
        ..error _ {} ..ok _ { abort }
    }
    match uri.decode_component(.text = "%Q0", .allocator = system.page_allocator) {
        ..error _ {} ..ok _ { abort }
    }
    invalid: [11]StringView = ("a b", "%", "%0G", "http://host:abc/", "http://[::1/", "a#b#c",
        "//[abc]/", "//[1::2::3]/", "//[::ffff:999.1.2.3]/", "//[user]@host/", "//user@@host/")
    for text in invalid {
        match uri.parse(.text = text) { ..error _ {} ..ok _ { abort } }
    }
}
