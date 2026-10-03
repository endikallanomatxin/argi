BackingAllocator : Type = (
    .page: $&PageAllocator
)

allocate(.self: $&BackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    result = allocate(.self = self&.page, .size = size, .alignment = alignment)
}

BackingAllocator deinit(.self: $&BackingAllocator) -> () := {}

BackingAllocator implements Allocator

EndBacking : Type = (
    .marker: Bool
)

EndBacking init(.backing: $&BackingAllocator) -> (.result: EndBacking) := {
    result = (.marker = false)
    deinit(.self = backing)
}

consume(.value: EndBacking) -> () := {}

end_backing(.backing: $&BackingAllocator) -> () := {
    consume(.value = EndBacking(.backing = backing))
}

main(.system: System) -> (.status_code: Int32) := {
    backing ::= BackingAllocator(.page = system.page_allocator)
    allocator ::= GeneralPurposeAllocator(.allocator = $&backing)
    end_backing(.backing = $&backing)
    result ::= allocate(.self = $&allocator, .size = 8)
    status_code = 0
}
