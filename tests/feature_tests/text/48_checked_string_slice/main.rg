main() -> (.status_code: Int32 = 0) := {
    text :: StringView = "café"
    whole ::= unwrap_or_abort(.value = slice(.self = text, .start = 0, .count = 5))
    if equals(.left = whole, .right = text).ok == false { abort }
    end ::= unwrap_or_abort(.value = slice(.self = text, .start = 5, .count = 0))
    if end.length != 0 { abort }
    part ::= unwrap_or_abort(.value = slice(.self = text, .start = 3, .count = 2))
    if equals(.left = part, .right = "é").ok == false { abort }
    match slice(.self = text, .start = 6, .count = 0) { ..ok _ { abort } ..error _ {} }
    match slice(.self = text, .start = 4, .count = 2) { ..ok _ { abort } ..error _ {} }
    native :: UIntNative = 0
    maximum ::= integer_limits(.value = native).maximum
    match slice(.self = text, .start = maximum, .count = maximum) { ..ok _ { abort } ..error _ {} }
    match slice(.self = text, .start = 1, .count = maximum) { ..ok _ { abort } ..error _ {} }
}
