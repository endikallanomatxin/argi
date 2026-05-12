main(.system: System = System()) -> (.status_code: Int32) := {
    text ::= String(.allocator = system.allocator, .length = 2)
    bytes_set(.string = $&text, .index = 0, .value = 79)
    bytes_set(.string = $&text, .index = 1, .value = 75)

    strings ::= DynamicArray#(.t: String)(.capacity = 1)
    #defer deinit(.self = $&strings, .allocator = system.allocator)
    push(.self = $&strings, .value = text, .allocator = system.allocator)

    first_ptr : &String = &strings[0]
    if bytes_get(.string = first_ptr, .index = 0).byte != 79 {
        status_code = 1
        return
    }

    mutable_ptr : $&String = $&strings[0]
    bytes_set(.string = mutable_ptr, .index = 0, .value = 78)

    if bytes_get(.string = &strings[0], .index = 0).byte != 78 {
        status_code = 2
        return
    }

    status_code = 0
}
