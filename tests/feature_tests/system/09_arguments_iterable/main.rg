main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    count :: UIntNative = length(.self = system.args).count
    if count < 1 {
        status_code = 1
        return
    }

    if has_argument(.self = system.args, .index = 0).ok {
    } else {
        status_code = 2
        return
    }

    seen :: UIntNative = 0
    first_length :: UIntNative = 0
    for arg in system.args {
        if seen == 0 {
            first_length = arg.length
        }
        seen = seen + 1
    }

    if seen != count {
        status_code = 3
        return
    }

    if first_length < 1 {
        status_code = 4
        return
    }

    if has_argument(.self = system.args, .index = count).ok {
        status_code = 5
        return
    }

    status_code = 0
}
