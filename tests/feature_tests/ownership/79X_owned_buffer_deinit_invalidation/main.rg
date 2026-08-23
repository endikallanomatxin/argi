read(.value: &UInt8) -> () := {}

main() -> (.status_code: Int32) := {
    allocator ::= CAllocator()
    data ::= allocate(.self = $&allocator, .size = 8)
    text :: String = (
        .allocation = (.data = data, .size = 8),
        .length = 0,
    )
    pointer : &UInt8 = text.allocation.data
    deinit(.self = $$&text, .allocator = $&allocator)
    read(.value = pointer)
    status_code = 0
}
