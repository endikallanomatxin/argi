main(.system: System = System()) -> (.status_code: Int32) := {
    left :: String = String(.allocator = system.allocator, .length = 5)
    bytes_set(.string = $&left, .index = 0, .value = 104)
    bytes_set(.string = $&left, .index = 1, .value = 101)
    bytes_set(.string = $&left, .index = 2, .value = 108)
    bytes_set(.string = $&left, .index = 3, .value = 108)
    bytes_set(.string = $&left, .index = 4, .value = 111)

    right :: String = String(.allocator = system.allocator, .length = 6)
    bytes_set(.string = $&right, .index = 0, .value = 32)
    bytes_set(.string = $&right, .index = 1, .value = 119)
    bytes_set(.string = $&right, .index = 2, .value = 111)
    bytes_set(.string = $&right, .index = 3, .value = 114)
    bytes_set(.string = $&right, .index = 4, .value = 108)
    bytes_set(.string = $&right, .index = 5, .value = 100)

    left_view ::= as_view(.self = &left)
    right_view ::= as_view(.self = &right)
    combined :: String = &left_view + &right_view

    if &combined == "hello world" {
        status_code = 0
    } else {
        status_code = 1
    }
}
