main := (.system: System) -> (.status_code: Int32 = 1) {
    assume writer ::= $&system.terminal&.stderr
    assume allocator := system.page_allocator
    array ::= DynamicArray#(.t: Int32)(.allocator = allocator, .capacity = 1)!!!
    borrowed ::= &array
    for ~item in borrowed {}
    status_code = 0
}
