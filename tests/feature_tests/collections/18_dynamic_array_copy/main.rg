main(.system: System = System()) -> (.status_code: Int32) := {
    arr ::= DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&arr, .allocator = system.allocator)

    push(.self = $&arr, .value = 10, .allocator = system.allocator)
    push(.self = $&arr, .value = 20, .allocator = system.allocator)

    copied :: DynamicArray#(.t: Int32) = arr
    #defer deinit(.self = $&copied, .allocator = system.allocator)

    copied[0] = 99
    push(.self = $&copied, .value = 30, .allocator = system.allocator)

    if arr.length != 2 {
        status_code = 1
        return
    }

    if copied.length != 3 {
        status_code = 2
        return
    }

    if arr[0] != 10 {
        status_code = 3
        return
    }

    if copied[0] != 99 {
        status_code = 4
        return
    }

    text ::= String(.allocator = system.allocator, .length = 2)
    bytes_set(.string = $&text, .index = 0, .value = 79)
    bytes_set(.string = $&text, .index = 1, .value = 75)

    strings ::= DynamicArray#(.t: String)(.capacity = 1)
    #defer deinit(.self = $&strings, .allocator = system.allocator)
    push(.self = $&strings, .value = text, .allocator = system.allocator)

    copied_strings :: DynamicArray#(.t: String) = strings
    #defer deinit(.self = $&copied_strings, .allocator = system.allocator)

    copied_first_addr ::= dynamic_array_element_address#(.t: String)(.array = &copied_strings, .offset = 0).address
    copied_first_ptr : &String = cast#(.to: &String)(.value = copied_first_addr)
    first_string ::= copy(.self = copied_first_ptr&, .allocator = system.allocator)
    #defer deinit(.self = $&first_string, .allocator = system.allocator)
    bytes_set(.string = $&first_string, .index = 0, .value = 78)
    copied_strings[0] = first_string

    original_first_addr ::= dynamic_array_element_address#(.t: String)(.array = &strings, .offset = 0).address
    original_first_ptr : &String = cast#(.to: &String)(.value = original_first_addr)
    original_first ::= copy(.self = original_first_ptr&, .allocator = system.allocator)
    #defer deinit(.self = $&original_first, .allocator = system.allocator)
    copied_first_after_addr ::= dynamic_array_element_address#(.t: String)(.array = &copied_strings, .offset = 0).address
    copied_first_after_ptr : &String = cast#(.to: &String)(.value = copied_first_after_addr)
    copied_first ::= copy(.self = copied_first_after_ptr&, .allocator = system.allocator)
    #defer deinit(.self = $&copied_first, .allocator = system.allocator)

    if bytes_get(.string = &original_first, .index = 0).byte != 79 {
        status_code = 5
        return
    }

    if bytes_get(.string = &copied_first, .index = 0).byte != 78 {
        status_code = 6
        return
    }

    status_code = 0
}
