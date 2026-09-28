unsafe_allocation := #import("../../_support/unsafe_allocation")
Container : Type = (
    .pointer: $&UInt8
)

read_nested(.container: $&Container) -> (.result: UInt8) := {
    result = container&.pointer&
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.backing_allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            container :: Container = (.pointer = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference)
            deinit(.self = $&allocation)
            observed ::= read_nested(.container = $&container).result
            if observed == 0 { status_code = 0 } else { status_code = 2 }
        }
    }
}
