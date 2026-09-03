FailFourthAllocator : Type = (
    .allocation_attempts: Int32
    .deallocations: Int32
    .backing_freed_after_elements: Bool
)

init(.p: $&FailFourthAllocator) -> () := {
    p& = (
        .allocation_attempts = 0,
        .deallocations = 0,
        .backing_freed_after_elements = false,
    )
}

allocate(.self: $&FailFourthAllocator, .size: UIntNative) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    self&.allocation_attempts = self&.allocation_attempts + 1
    if self&.allocation_attempts == 4 {
        result = ..error(.reason = ..out_of_memory)
        return
    }
    storage ::= malloc(.size = size)
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&FailFourthAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    three :: UIntNative = 3
    if size == three * size_of(.type = String) {
        self&.backing_freed_after_elements = self&.deallocations == 2
    }
    self&.deallocations = self&.deallocations + 1
    address :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.address = address)
}

FailFourthAllocator implements Allocator
FailFourthAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32 = 0) := {
    source ::= DynamicArray#(.t: String)(.capacity = 3)
    #defer deinit#(.t: String)(.self = $&source)

    first ::= String(.length = 1)
    second ::= String(.length = 1)
    third ::= String(.length = 1)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~first)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~second)
    push_assume_capacity#(.t: String)(.self = $&source, .value = ~third)

    failing ::= FailFourthAllocator()
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
