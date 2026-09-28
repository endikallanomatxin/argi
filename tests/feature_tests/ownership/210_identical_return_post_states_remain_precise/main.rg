unsafe_allocation := #import("../../_support/unsafe_allocation")
Holder : Type = (.reference: $&UInt8)

replace(.holder: $&Holder, .condition: Bool, .reference: $&UInt8) -> () := {
    if condition {
        holder&.reference = reference
        return
    }
    holder&.reference = reference
}

main(.system: System, .condition: Bool = true) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    result ::= allocate(.self = $&allocator_storage, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            holder ::= Holder(.reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference)
            replace(.holder = $&holder, .condition = condition, .reference = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference)
            observed ::= holder.reference&
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
