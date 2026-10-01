expect_segment(.iterator: $&Iterator#(.t: StringView), .expected: StringView) -> () := {
    if has_next(.self = iterator).ok == false { abort }
    segment ::= next(.self = iterator).value
    if equals(.left = segment, .right = expected).ok == false { abort }
}
first_segment(.text: StringView) -> (.view: StringView) := {
    iterator ::= unwrap_or_abort(.value = split(.self = text, .separator = ","))
    view = next(.self = $&iterator).value
}
main() -> (.status_code: Int32 = 0) := {
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
    bytes : [3]UInt8 = (97, 0, 98)
    binary :: StringView = (.data = &bytes[0], .length = 3)
    separator :: StringView = (.data = &bytes[1], .length = 1)
    zero ::= unwrap_or_abort(.value = split(.self = binary, .separator = separator))
    expect_segment(.iterator = $&zero, .expected = "a")
    expect_segment(.iterator = $&zero, .expected = "b")
}
