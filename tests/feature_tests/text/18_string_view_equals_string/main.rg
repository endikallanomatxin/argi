main(.system: System = System()) -> (.status_code: Int32) := {
    text :: String = String(.allocator = system.allocator, .length = 5)
    bytes_set(.string = $&text, .index = 0, .value = 104)
    bytes_set(.string = $&text, .index = 1, .value = 101)
    bytes_set(.string = $&text, .index = 2, .value = 108)
    bytes_set(.string = $&text, .index = 3, .value = 108)
    bytes_set(.string = $&text, .index = 4, .value = 111)

    text_view ::= as_view(.self = &text)
    text_view_again ::= as_view(.self = &text)
    if text_view == text_view_again {
        status_code = 0
    } else {
        status_code = 1
    }
}
