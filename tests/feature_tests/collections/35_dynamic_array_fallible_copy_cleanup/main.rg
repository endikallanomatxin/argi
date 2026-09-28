FailFourthAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .allocation_attempts: Int32
    .deallocations: Int32
    .backing_freed_after_elements: Bool
)

init(.p: $&FailFourthAllocator, .ffi: $&ForeignFunctionInterface) -> () := {
    p&.ffi = ffi
    p&.allocation_attempts = 0
    p&.deallocations = 0
    p&.backing_freed_after_elements = false
}

allocate(.self: $&FailFourthAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.allocation_attempts = self&.allocation_attempts + 1
    if self&.allocation_attempts == 4 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&FailFourthAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    three :: UIntNative = 3
    if size == three * size_of(.type = String) {
        self&.backing_freed_after_elements = self&.deallocations == 2
    }
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = data.address
    free(.address = address, .ffi = self&.ffi)
}

FailFourthAllocator implements Allocator
FailFourthAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    source ::= DynamicArray#(.t: String)(.capacity = 3)
    #defer deinit#(.t: String)(.self = $&source)

    first ::= String(.length = 1)
    second ::= String(.length = 1)
    third ::= String(.length = 1)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~first)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~second)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~third)

    failing ::= FailFourthAllocator(.ffi = system.ffi)
    copied ::= copy(.self = &source, .allocator = $&failing)
    if is(.value = copied, .variant = ..ok) {
        status_code = 1
        return
    }
    if failing.allocation_attempts != 4 or failing.deallocations != 3 {
        status_code = 2
        return
    }
    if failing.backing_freed_after_elements == false {
        status_code = 3
    }
}
