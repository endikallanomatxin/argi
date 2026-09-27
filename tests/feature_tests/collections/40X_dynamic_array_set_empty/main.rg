main (.system: System) -> (.status_code: Int32) := {
    assume allocator ::= system.allocator
    values :: DynamicArray#(.t: Int32) = DynamicArray#(.t: Int32)(.capacity = 1)
    #defer deinit(.self = $&values)

    index :: UIntNative = 0
    set_result ::= set(.self = $&values, .index = index, .value = 42, .allocator = system.allocator).result
    if is(.value = set_result, .variant = ..error) {
        if is(.value = set_result..error.reason, .variant = ..out_of_bounds) {
            status_code = 0
        } else {
            status_code = 1
        }
    } else {
        status_code = 2
    }
}
