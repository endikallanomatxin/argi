main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&array, .allocator = system.allocator)
    value ::= _trusted_dynamic_array_get#(.t: Int32)(.array = &array, .index = 0)
    status_code = value
}
