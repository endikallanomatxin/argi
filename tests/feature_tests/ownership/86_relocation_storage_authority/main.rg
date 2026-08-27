main() -> (.status_code: Int32) := {
    storage ::= malloc(.size = 1).address
    destination :: UIntNative
    relocate(.source = $&storage, .destination = $&destination)
    allocator :: CAllocator
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&allocator)
    allocation ::= establish_allocation(.storage = destination, .size = 1, .deallocator = deallocator)
    deinit(.self = $&allocation)
    status_code = 0
}
