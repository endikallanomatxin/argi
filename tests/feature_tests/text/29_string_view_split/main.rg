expect_segment := #(.T: Type: Iterator#(T)) (
    .iterator: $&T, .expected: StringView, .error_tracer: $&Virtual#(ErrorTracer)
) -> () {
    assume error_tracer
    if has_next(.self = iterator).ok == false { abort }
    segment ::= next(.self = iterator).value
    if segment != expected { abort }
}

first_segment := (.text: StringView, .error_tracer: $&Virtual#(ErrorTracer)) -> (
    .view : StringView
) {
    assume error_tracer
    iterator ::= unwrap_or_abort(.value = split(.self = text, .separator = ","))
    view = next(.self = $&iterator).value
}

main := () -> (.status_code: Int32 = 0) {
    assume error_tracer ::= $&noop_error_tracer
    if is(.value = split(.self = "abc", .separator = ""), .variant = ..ok) { abort }
    empty ::= unwrap_or_abort(.value = split(.self = "", .separator = ","))
    expect_segment(.iterator = $&empty, .expected = "")
    if has_next(.self = &empty).ok { abort }
    parts ::= unwrap_or_abort(.value = split(.self = ",a,,b,", .separator = ","))
    expect_segment(.iterator = $&parts, .expected = "")
    first ::= next(.self = $&parts).value
    if first != "a" { abort }
    expect_segment(.iterator = $&parts, .expected = "")
    expect_segment(.iterator = $&parts, .expected = "b")
    expect_segment(.iterator = $&parts, .expected = "")
    if first != "a" { abort }
    if has_next(.self = &parts).ok { abort }
    multi ::= unwrap_or_abort(.value = split(.self = "a--b----", .separator = "--"))
    expect_segment(.iterator = $&multi, .expected = "a")
    expect_segment(.iterator = $&multi, .expected = "b")
    expect_segment(.iterator = $&multi, .expected = "")
    expect_segment(.iterator = $&multi, .expected = "")
    if has_next(.self = &multi).ok { abort }
    overlap ::= unwrap_or_abort(.value = split(.self = "aaa", .separator = "aa"))
    expect_segment(.iterator = $&overlap, .expected = "")
    expect_segment(.iterator = $&overlap, .expected = "a")
    longer ::= unwrap_or_abort(.value = split(.self = "a", .separator = "ab"))
    expect_segment(.iterator = $&longer, .expected = "a")
    if first_segment(.text = "first,second").view != "first" { abort }
    bytes: [3]UInt8 = (97, 0, 98)
    binary: StringView = "a\0b"
    separator: StringView = "\0"
    zero ::= unwrap_or_abort(.value = split(.self = binary, .separator = separator))
    expect_segment(.iterator = $&zero, .expected = "a")
    expect_segment(.iterator = $&zero, .expected = "b")
    trimmed ::= trim(.self = " \tñ, € ,🙂\r\n").view
    unicode_parts ::= unwrap_or_abort(.value = split(.self = trimmed, .separator = ","))
    first_unicode ::= next(.self = $&unicode_parts).value
    middle_unicode ::= trim(.self = next(.self = $&unicode_parts).value).view
    expect_segment(.iterator = $&unicode_parts, .expected = "🙂")
    if first_unicode != "ñ" or middle_unicode != "€" { abort }
    if has_next(.self = &unicode_parts).ok { abort }
    if trim(.self = " \t\r\n").view != "" { abort }
    if trim_start(.self = "  x  ").view != "x  " { abort }
    if trim_end(.self = "  x  ").view != "  x" { abort }
    if trim(.self = " x ").view != " x " { abort }
    nul ::= trim(.self = " \0 ").view
    if byte_length(&nul).count != 1 { abort }
    if unwrap_or_abort(.value = bytes_get(.view = &nul, .index = 0)) != 0 { abort }
}
