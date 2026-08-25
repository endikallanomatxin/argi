read(.value: &UInt8) -> () := {}

main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    init(.p = $&allocator)
    data ::= allocate(.self = $&allocator, .size = 1)
    read(.value = data)
    deallocate(.self = $&allocator, .data = data, .size = 1)
    status_code = 0
}
