main(.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    vacant ::= trusted_dynamic_array_storage_pointer#(.t: Int32)(.array = $&array, .offset = 0).pointer
    status_code = vacant&
}
