BackingAllocator : Type = (
    .page: $&PageAllocator
)

allocate(.self: $&BackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    result = allocate(.self = self&.page, .size = size, .alignment = alignment)
}

deinit(.self: $&BackingAllocator) -> () := {}

BackingAllocator implements Allocator

EndBacking : Type = (
    .marker: Bool
)

init(.p: $&EndBacking, .backing: $&BackingAllocator) -> () := {
    p& = (.marker = false)
    deinit(.self = backing)
}

consume(.value: EndBacking) -> () := {}

main(.system: System) -> (.status_code: Int32) := {
    backing ::= BackingAllocator(.page = system.page_allocator)
    allocator ::= GeneralPurposeAllocator(.backing_allocator = $&backing)
    consume(.value = EndBacking(.backing = $&backing))
    result ::= allocate(.self = $&allocator, .size = 8)
    status_code = 0
}
