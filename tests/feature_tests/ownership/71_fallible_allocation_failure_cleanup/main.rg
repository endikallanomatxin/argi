FailingAllocator : Type = (
    .allocations: Int32
    .deallocations: Int32
)

allocate(.self: $&FailingAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    self&.allocations = self&.allocations + 1
    zero :: UIntNative = 0
    raw ::= raw_pointer#(.t: UInt8)(.address = zero)
    data ::= establish_inherited_reference#(.t: UInt8)(
        .raw = raw,
        .root = cast#(.to: &Any)(.value = self),
    ).reference
    deallocator ::= to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = (
        .data = data,
        .size = size,
        .deallocator = deallocator,
    )
}

deallocate(.self: $&FailingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    self&.deallocations = self&.deallocations + 1
}

FailingAllocator implements Allocator
FailingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: FailingAllocator = (
        .allocations = 0,
        .deallocations = 0,
    )
    result ::= allocate_fallible(.self = $&allocator, .size = 8)
    if is(.value = result, .variant = ..error) {
        status_code = allocator.allocations * 10 + allocator.deallocations - 11
        return
    }
    status_code = 1
}
