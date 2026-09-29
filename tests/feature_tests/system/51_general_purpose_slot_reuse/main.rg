TrackingAllocator : Type = (
    .backing: $&PageAllocator
    .allocations: UIntNative
    .deallocations: UIntNative
)

allocate(.self: $&TrackingAllocator, .size: UIntNative, .alignment: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    allocated ::= allocate(.self = self&.backing, .size = size, .alignment = alignment)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            original ::= ~payload
            self&.allocations = self&.allocations + 1
            -- Tracking delegates release to the same backing allocator.
            original.deallocator = to_virtual#(.abstract: Deallocator)(.value = self)
            result = ..ok ~original
        }
    }
}

deallocate(.self: $&TrackingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    deallocate(.self = self&.backing&.memory, .data = data, .size = size, .alignment = alignment)
}
TrackingAllocator implements Allocator
TrackingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    tracker :: TrackingAllocator = (.backing = system.page_allocator, .allocations = 0, .deallocations = 0)
    allocator ::= GeneralPurposeAllocator(.allocator = $&tracker)
    -- The receipt list uses a separate allocator so backing counts describe
    -- only the size class under test: one chunk holds 512 eight-byte slots.
    receipts ::= unwrap_or_abort(.value = DynamicArray#(.t: Allocation)(.allocator = system.page_allocator, .capacity = 512))
    i :: UIntNative = 0
    first_address :: UIntNative = 0
    middle_address :: UIntNative = 0
    last_address :: UIntNative = 0
    while i < 512 {
        allocated ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
        match allocated {
            ..error _ { status_code = 1
                return }
            ..ok ~ payload {
                receipt ::= ~payload
                if i == 0 { first_address = receipt.data.address }
                if i == 64 { middle_address = receipt.data.address }
                if i == 511 { last_address = receipt.data.address }
                push_assume_capacity#(.t: Allocation)(.self = $&receipts, .value = ~receipt)
            }
        }
        i = i + 1
    }
    if tracker.allocations != 1 { status_code = 2
        return }
    -- Free out of order, crossing bitmap words and including the last slot.
    last_result ::= pop#(.t: Allocation)(.self = $&receipts).result
    if is(.value = last_result, .variant = ..error) { status_code = 9
        return }
    last ::= ~last_result..ok
    deinit(.self = $&last)
    middle_result ::= remove#(.t: Allocation)(.self = $&receipts, .i = 64).result
    if is(.value = middle_result, .variant = ..error) { status_code = 9
        return }
    middle ::= ~middle_result..ok
    deinit(.self = $&middle)
    first_result ::= remove#(.t: Allocation)(.self = $&receipts, .i = 0).result
    if is(.value = first_result, .variant = ..error) { status_code = 9
        return }
    first ::= ~first_result..ok
    deinit(.self = $&first)
    i = 0
    while i < 3 {
        allocated ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
        match allocated {
            ..error _ { status_code = 3
                return }
            ..ok ~ payload {
                receipt ::= ~payload
                expected ::= first_address
                if i == 1 { expected = middle_address }
                if i == 2 { expected = last_address }
                if receipt.data.address != expected { status_code = 4
                    return }
                push_assume_capacity#(.t: Allocation)(.self = $&receipts, .value = ~receipt)
            }
        }
        i = i + 1
    }
    -- Keep the other slots live while repeatedly freeing and reacquiring one.
    i = 0
    while i < 600 {
        released_result ::= pop#(.t: Allocation)(.self = $&receipts).result
        if is(.value = released_result, .variant = ..error) { status_code = 9
            return }
        released ::= ~released_result..ok
        deinit(.self = $&released)
        allocated ::= allocate(.self = $&allocator, .size = 8, .alignment = 8)
        match allocated {
            ..error _ { status_code = 5
                return }
            ..ok ~ payload {
                receipt ::= ~payload
                if receipt.data.address != last_address { status_code = 6
                    return }
                push_assume_capacity#(.t: Allocation)(.self = $&receipts, .value = ~receipt)
            }
        }
        i = i + 1
    }
    if tracker.allocations != 1 or tracker.deallocations != 0 { status_code = 7
        return }
    deinit#(.t: Allocation)(.self = $&receipts, .allocator = system.page_allocator)
    if tracker.deallocations != 1 or has_live_allocations(.self = &allocator).has_live { status_code = 8 }
}
