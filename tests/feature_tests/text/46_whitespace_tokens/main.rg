main() -> (.status_code: Int32 = 0) := {
    iterator ::= split_whitespace(.self = "  one\t café\r\n🙂  ")
    if has_next(.self = &iterator).ok == false { abort }
    if has_next(.self = &iterator).ok == false { abort }
    first ::= next(.self = $&iterator).value
    second ::= next(.self = $&iterator).value
    third ::= next(.self = $&iterator).value
    if equals(.left = first, .right = "one").ok == false { abort }
    if equals(.left = second, .right = "café").ok == false { abort }
    if equals(.left = third, .right = "🙂").ok == false { abort }
    if has_next(.self = &iterator).ok { abort }
    empty ::= split_whitespace(.self = "")
    spaces ::= split_whitespace(.self = " \t\r\n")
    if has_next(.self = &empty).ok or has_next(.self = &spaces).ok { abort }
    count :: UIntNative = 0
    words ::= split_whitespace(.self = "one two three")
    while has_next(.self = &words).ok {
        word ::= next(.self = $&words).value
        if word.length == 0 { abort }
        count = count + 1
    }
    if count != 3 { abort }
    count = 0
    for word in split_whitespace(.self = "one two three") {
        if word.length == 0 { abort }
        count = count + 1
    }
    if count != 3 { abort }

}
