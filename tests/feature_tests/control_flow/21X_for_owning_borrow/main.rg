main(.system: System) -> !Void = ..ok Void() := {
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 1)!
    borrowed ::= &array
    for ~item in borrowed {}
}
