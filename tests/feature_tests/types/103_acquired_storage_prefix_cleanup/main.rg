TrackingDeallocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .released_size: UIntNative
    .released_alignment: UIntNative
)
deallocate(.self: $&TrackingDeallocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.released_size = size
    self&.released_alignment = alignment
    free(.address = data.address, .ffi = self&.ffi)
}
TrackingDeallocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    tracker :: TrackingDeallocator = (.ffi = system.ffi, .released_size = 0, .released_alignment = 0)
    storage ::= unwrap_or_abort(.value = acquire_heap_storage(.size = 32, .alignment = 16, .ffi = system.ffi))
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = $&tracker)
    allocation ::= establish_allocation(.storage = ~storage, .size = 8, .alignment = 8, .deallocator = deallocator).allocation
    if allocation.size != 8 or allocation.alignment != 8 { status_code = 1 }
    allocation.size = 0
    allocation.alignment = 0
    deinit(.self = $&allocation)
    if tracker.released_size != 32 or tracker.released_alignment != 16 { status_code = 2 }
}
