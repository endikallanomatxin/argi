read(.value: &Int32) -> () := {}

main(.system: System = System()) -> (.status_code: Int32) := {
    array ::= DynamicArray#(.t: Int32)(.capacity = 1)
    push(.self = $$&array, .value = 10, .allocator = system.allocator)
    pointer : &Int32 = &array[0]

    deinit(.self = $$&array, .allocator = system.allocator)
    read(.value = pointer)
    status_code = 0
}
