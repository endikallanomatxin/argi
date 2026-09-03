main(.system: System) -> (.status_code: Int32 = 0) := {
    array ::= DynamicArray#(.t: String)(.capacity = 1)
    #defer deinit#(.t: String)(.self = $&array)
    text ::= String(.length = 1)
    bytes_set(.string = $&text, .index = 0, .value = 65)
    pushed ::= push#(.t: String)(.self = $&array, .value = ~text)
    if is(.value = pushed, .variant = ..error) {
        status_code = 1
        return
    }

    copied_result ::= copy(.self = &array, .allocator = system.allocator)
    match copied_result {
        ..error _ { status_code = 2 }
        ..ok ~ copied_payload {
            copied ::= ~copied_payload
            #defer deinit#(.t: String)(.self = $&copied)
            original ::= dynamic_array_element_ro_pointer#(.t: String)(.array = &array, .offset = 0).pointer
            duplicate ::= dynamic_array_element_rw_pointer#(.t: String)(.array = $&copied, .offset = 0).pointer
            bytes_set(.string = duplicate, .index = 0, .value = 66)
            if bytes_get(.string = original, .index = 0).byte != 65 {
                status_code = 3
                return
            }
            if bytes_get(.string = duplicate, .index = 0).byte != 66 {
                status_code = 4
            }
        }
    }
}
