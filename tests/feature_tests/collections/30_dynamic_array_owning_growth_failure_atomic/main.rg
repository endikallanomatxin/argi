Tracked : Type = (
    .id: Int32
    .allocation: Allocation
)

first_drops :: Int32 = 0
second_drops :: Int32 = 0

deinit(.self: $&Tracked) -> () := {
    if self&.id == 1 { first_drops = first_drops + 1 }
    if self&.id == 2 { second_drops = second_drops + 1 }
    deinit(.self = $&self&.allocation)
}

make_tracked(.allocator: $&Allocator, .id: Int32) -> (.result: Errable#(.t: Tracked, .reasons: (..out_of_memory))) := {
    assume allocator

    allocated ::= allocate(.self = allocator, .size = 1)
    match allocated {
        ..error _ { result = ..error(.reason = ..out_of_memory) }
        ..ok ~ payload {
            value ::= Tracked(.id = id, .allocation = ~payload)
            result = ..ok ~value
        }
    }
}

FailSecondAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .allocations: Int32
    .deallocations: Int32
)

init(.p: $&FailSecondAllocator, .ffi: $&ForeignFunctionInterface) -> () := {
    p&.ffi = ffi
    p&.allocations = 0
    p&.deallocations = 0
}

allocate(.self: $&FailSecondAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    if self&.allocations != 0 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    self&.allocations = self&.allocations + 1
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&FailSecondAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = data.address
    free(.address = address, .ffi = self&.ffi)
}

FailSecondAllocator implements Allocator
FailSecondAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    backing ::= FailSecondAllocator(.ffi = system.ffi)
    array ::= DynamicArray#(.t: Tracked)(.allocator = $&backing, .capacity = 1)
    first_result ::= make_tracked(.allocator = $&allocator_storage, .id = 1)
    match first_result {
        ..error _ { status_code = 1 }
        ..ok ~ first_payload {
            first ::= ~first_payload
            first_push ::= push#(.t: Tracked)(.allocator = $&backing, .self = $&array, .value = ~first)
            if is(.value = first_push, .variant = ..error) {
                status_code = 2
                return
            }

            second_result ::= make_tracked(.allocator = $&allocator_storage, .id = 2)
            match second_result {
                ..error _ { status_code = 3 }
                ..ok ~ second_payload {
                    second ::= ~second_payload
                    second_push ::= push#(.t: Tracked)(.allocator = $&backing, .self = $&array, .value = ~second)
                    if is(.value = second_push, .variant = ..ok) {
                        status_code = 4
                        return
                    }
                    remaining_result ::= get_ro_ref#(.t: Tracked)(.self = &array, .index = 0).result
                    if is(.value = remaining_result, .variant = ..error) {
                        status_code = 5
                        return
                    }
                    remaining ::= remaining_result..ok
                    if length#(.t: Tracked)(.self = &array).count != 1 or capacity#(.t: Tracked)(.self = &array).count != 1 or remaining&.id != 1 {
                        status_code = 5
                        return
                    }
                    if first_drops != 0 {
                        status_code = 6
                        return
                    }
                    if second_drops != 1 {
                        status_code = 8
                        return
                    }
                    deinit#(.t: Tracked)(.allocator = $&backing, .self = $&array)
                    if first_drops != 1 or second_drops != 1 or backing.deallocations != 1 {
                        status_code = 7
                        return
                    }
                }
            }
        }
    }
}
