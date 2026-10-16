expect_bounds#(.Text: Type: TextBytes#(Text))(.text: &Text) -> () := {
    size ::= byte_length(text).count
    match bytes_get(.view = text, .index = size) {
        ..ok _ { abort }
        ..error error { match error.reason { ..out_of_bounds {} } }
    }
    maximum ::= integer_limits(.value = size).maximum
    match bytes_get(.view = text, .index = maximum) {
        ..ok _ { abort }
        ..error error { match error.reason { ..out_of_bounds {} } }
    }
}

main(.system: System) -> () := {
    assume allocator ::= system.page_allocator
    text ::= unwrap_or_abort(.value = String(.length = 3))
    _ ::= unwrap_or_abort(.value = set_ascii($&text, .index = 0, .byte = 65))
    _ ::= unwrap_or_abort(.value = set_ascii($&text, .index = 2, .byte = 90))
    borrowed ::= view(&text)
    expect_bounds(.text = &text)
    expect_bounds(.text = &borrowed)
    if unwrap_or_abort(.value = bytes_get(.view = &text, .index = 1)) != 0 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &borrowed, .index = 2)) != 90 { abort }
    reference ::= unwrap_or_abort(.value = string_byte_reference(.string = &text, .index = 0))
    view_reference ::= unwrap_or_abort(.value = string_view_byte_address(&borrowed, .index = 2))
    if reference&!= 65 or view_reference&!= 90 { abort }
    match string_byte_reference(.string = &text, .index = 3) {
        ..ok _ { abort }
        ..error _ {}
    }
    match string_view_byte_address(&borrowed, .index = 3) {
        ..ok _ { abort }
        ..error _ {}
    }
    clear($&text)
    empty ::= view(&text)
    expect_bounds(.text = &text)
    expect_bounds(.text = &empty)
    match string_byte_reference(.string = &text, .index = 0) {
        ..ok _ { abort }
        ..error _ {}
    }
    match string_view_byte_address(&empty, .index = 0) {
        ..ok _ { abort }
        ..error _ {}
    }
    literal ::= ""
    expect_bounds(.text = &literal)
    -- The C representation remains terminated even though byte access is empty.
    c_text ::= as_c_string(&text).text
    if c_text&!= 0 { abort }
}
