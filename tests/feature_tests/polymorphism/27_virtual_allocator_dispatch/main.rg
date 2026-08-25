main(.system: System) -> (.status_code: Int32) := {
    allocator :: Virtual#(.abstract: Allocator) = to_virtual#(.abstract: Allocator)(.value = system.allocator)
    size :: UIntNative = 1
    data ::= allocate(.self = $&allocator, .size = size)
    data& = 7
    if data& == 7 {
        status_code = 0
    } else {
        status_code = 1
    }
    deallocate(.self = $&allocator, .data = data, .size = size)
}
