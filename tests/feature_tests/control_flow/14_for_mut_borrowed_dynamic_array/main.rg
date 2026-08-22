main(.system: System = System()) -> (.status_code: Int32) := {
    dyn ::= DynamicArray#(.t: Int32)(.capacity = 2)
    #defer deinit(.self = $$&dyn, .allocator = system.allocator)
    push(.self = $$&dyn, .value = 7, .allocator = system.allocator)
    push(.self = $$&dyn, .value = 8, .allocator = system.allocator)

    for $& value in dyn {
        value& = value& + 10
    }

    if dyn[0] != 17 {
        status_code = 1
        return
    }

    if dyn[1] != 18 {
        status_code = 2
        return
    }

    status_code = 0
}
