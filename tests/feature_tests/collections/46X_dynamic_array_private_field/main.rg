main (.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    array._length = 100
    status_code = 0
}
