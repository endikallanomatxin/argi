main() -> (.status_code: Int32 = 0) := {
    byte :: UInt8 = 0
    digits :: UIntNative = 0
    letters :: UIntNative = 0
    whitespace :: UIntNative = 0
    ascii :: UIntNative = 0
    while true {
        if ascii_is_digit(.byte = byte).ok { digits = digits + 1 }
        if ascii_is_alpha(.byte = byte).ok { letters = letters + 1 }
        if ascii_is_whitespace(.byte = byte).ok { whitespace = whitespace + 1 }
        if ascii_is_ascii(.byte = byte).ok { ascii = ascii + 1 }
        lower ::= ascii_to_lower(.byte = byte).value
        upper ::= ascii_to_upper(.byte = byte).value
        if ascii_to_lower(.byte = lower).value != lower { abort }
        if ascii_to_upper(.byte = upper).value != upper { abort }
        if byte >= 128 and [lower != byte or upper != byte] { abort }
        if ascii_is_alpha(.byte = byte).ok {
            if ascii_is_lower(.byte = lower).ok == false { abort }
            if ascii_is_upper(.byte = upper).ok == false { abort }
        } else { if lower != byte or upper != byte { abort } }
        if byte == 255 { break }
        byte = byte + 1
    }
    if digits != 10 or letters != 52 or whitespace != 6 or ascii != 128 { abort }
    if ascii_to_lower(.byte = 65).value != 97 { abort }
    if ascii_to_upper(.byte = 122).value != 90 { abort }
    match find_last(.self = "ababa", .pattern = "aba").index {
        ..none { abort }
        ..some hit { if hit.value != 2 { abort } }
    }
    match find_last(.self = "abc", .pattern = "").index {
        ..none { abort }
        ..some hit { if hit.value != 3 { abort } }
    }
    match find_last(.self = "", .pattern = "a").index { ..none {} ..some _ { abort } }
    if equals(.left = trim(.self = " \t\r\nword ").view, .right = "word").ok == false { abort }
}
