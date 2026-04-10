main(.system: System = System()) -> (.status_code: Int32) := {
    left :: String = String(.allocator = system.allocator, .length = 5)
    bytes_set(.string = $&left, .index = 0, .value = 104)
    bytes_set(.string = $&left, .index = 1, .value = 101)
    bytes_set(.string = $&left, .index = 2, .value = 108)
    bytes_set(.string = $&left, .index = 3, .value = 108)
    bytes_set(.string = $&left, .index = 4, .value = 111)

    left_view ::= as_view(.self = &left)
    combined :: String = &left_view + "\n"

    combined_view ::= as_view(.self = &combined)

    if combined_view == "hello\n" {
        status_code = 0
    } else {
        status_code = 1
    }
}
