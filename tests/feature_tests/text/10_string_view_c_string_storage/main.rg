CountingAllocator : Type = (
    .ffi: $&ForeignFunctionInterface
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative, .alignment: UIntNative = 1) -> (.result: Errable#(.t: Allocation, .reasons: (..out_of_memory))) := {
    storage ::= malloc(.size = size, .ffi = self&.ffi)
    raw_addr :: UIntNative = UIntNative(.value = storage)
    self& = (
        .ffi = self&.ffi,
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation ::= establish_allocation(.storage = storage, .size = size, .alignment = alignment, .deallocator = deallocator)
    result = ..ok ~allocation
}

deallocate(.self: $&CountingAllocator, .data: RawPointer#(.t: UInt8), .size: UIntNative, .alignment: UIntNative) -> () := {
    raw_addr :: UIntNative = data.address
    free(.address = raw_addr, .ffi = self&.ffi)
    self& = (
        .ffi = self&.ffi,
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage :: CountingAllocator = (
        .ffi = system.ffi,
        .alloc_count = 0,
        .dealloc_count = 0,
    )
    assume allocator ::= $&allocator_storage

    literal ::= from_literal(.data = "abc")
    data ::= reinterpret_reference#(.from: Char, .to: UInt8)(.base = literal).reference

    if 1 == 1 {
        borrowed_view : StringView = (
            .data = data,
            .length = 3,
        )
        borrowed_result ::= as_c_string(.self = borrowed_view, .allocator = $&allocator_storage)
        match borrowed_result {
        ..error _ { status_code = 7 }
        ..ok ~ borrowed {
        if borrowed.storage.size != 4 {
            status_code = 1
            return
        }
        if allocator_storage.alloc_count != 1 {
            status_code = 2
            return
        }
        }
        }
    }

    if allocator_storage.dealloc_count != 1 {
        status_code = 3
        return
    }

    if 1 == 1 {
        copied_view : StringView = (
            .data = data,
            .length = 2,
        )
        copied_result ::= as_c_string(.self = copied_view, .allocator = $&allocator_storage)
        match copied_result {
        ..error _ { status_code = 8 }
        ..ok ~ copied {
        if copied.storage.size != 3 {
            status_code = 4
            return
        }
        if allocator_storage.alloc_count != 2 {
            status_code = 5
            return
        }
        }
        }
    }

    if allocator_storage.dealloc_count != 2 {
        status_code = 6
        return
    }

    status_code = 0
}
