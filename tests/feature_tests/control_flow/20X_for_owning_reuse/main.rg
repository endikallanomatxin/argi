main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 1)!
    for ~item in array {}
    length(.self = &array)
}
