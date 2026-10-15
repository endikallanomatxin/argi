expect_position(.text: StringView, .pattern: StringView, .expected: UIntNative) -> () := {
    match find(.self = text, .pattern = pattern).index {
        ..none { abort }
        ..some payload { if payload.value != expected { abort } }
    }
}

main() -> (.status_code: Int32 = 0) := {
    expect_position(.text = "", .pattern = "", .expected = 0)
    expect_position(.text = "abc", .pattern = "", .expected = 0)
    expect_position(.text = "abc", .pattern = "abc", .expected = 0)
    expect_position(.text = "abcabc", .pattern = "bc", .expected = 1)
    expect_position(.text = "aaab", .pattern = "aab", .expected = 1)
    expect_position(.text = "abc", .pattern = "c", .expected = 2)
    expect_position(.text = "éx", .pattern = "x", .expected = 2)
    if contains(.self = "", .pattern = "a").ok { abort }
    if contains(.self = "ab", .pattern = "abc").ok { abort }
    if contains(.self = "abc", .pattern = "d").ok { abort }
    if contains(.self = "abc", .pattern = "bc").ok == false { abort }
    if starts_with(.self = "", .pattern = "").ok == false { abort }
    if ends_with(.self = "", .pattern = "").ok == false { abort }
    if starts_with(.self = "abc", .pattern = "ab").ok == false { abort }
    if ends_with(.self = "abc", .pattern = "bc").ok == false { abort }
    if starts_with(.self = "abc", .pattern = "bc").ok { abort }
    if ends_with(.self = "abc", .pattern = "ab").ok { abort }
    if starts_with(.self = "ab", .pattern = "abc").ok { abort }
    if ends_with(.self = "ab", .pattern = "abc").ok { abort }
    bytes: [3]UInt8 = (97, 0, 98)
    text :: StringView = (.data = &bytes[0], .length = 3)
    zero :: StringView = (.data = &bytes[1], .length = 1)
    expect_position(.text = text, .pattern = zero, .expected = 1)
    expect_position(.text = text, .pattern = "b", .expected = 2)
    bounded :: StringView = (.data = &bytes[0], .length = 1)
    if contains(.self = bounded, .pattern = "b").ok { abort }
}
