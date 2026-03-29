main(.system: System = System()) -> (.status_code: Int32) := {
    line :: String = String(.allocator = system.allocator, .length = 5)
    bytes_set(.string = $&line, .index = 0, .value = 104)
    bytes_set(.string = $&line, .index = 1, .value = 101)
    bytes_set(.string = $&line, .index = 2, .value = 108)
    bytes_set(.string = $&line, .index = 3, .value = 108)
    bytes_set(.string = $&line, .index = 4, .value = 111)

    with_newline :: String = &line + "\n"

    if &with_newline == "hello\n" {
        status_code = 0
    } else {
        status_code = 1
    }
}
