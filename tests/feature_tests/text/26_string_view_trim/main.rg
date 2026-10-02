forward(.text: StringView) -> (.view: StringView) := {
    view = trim(.self = text).view
}
main() -> (.status_code: Int32 = 0) := {
    if trim(.self = "").view != "" { abort }
    if trim(.self = " \t\r\n ").view != "" { abort }
    if trim(.self = "hello").view != "hello" { abort }
    if trim(.self = " \t hello \r\n").view != "hello" { abort }
    if trim_start(.self = "  hello  ").view != "hello  " { abort }
    if trim_end(.self = "  hello  ").view != "  hello" { abort }
    if trim(.self = " a b ").view != "a b" { abort }
    if trim(.self = " x ").view != " x " { abort }
    bytes : [8]UInt8 = (9, 10, 11, 12, 13, 32, 120, 32)
    all :: StringView = (.data = &bytes[0], .length = 8)
    trimmed ::= forward(.text = all).view
    if trimmed != "x" { abort }
    if UIntNative(.value = trimmed.data) != UIntNative(.value = &bytes[6]) { abort }
    binary : [3]UInt8 = (32, 0, 32)
    zeros :: StringView = (.data = &binary[0], .length = 3)
    zero ::= trim(.self = zeros).view
    if zero.length != 1 { abort }
    if bytes_get(.view = &zero, .index = 0).byte != 0 { abort }
}
