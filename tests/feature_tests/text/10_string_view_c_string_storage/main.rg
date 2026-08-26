CountingAllocator : Type = (
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.allocation: Allocation) := {
    storage ::= malloc(.size = size)
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = storage)
    self& = (
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    deallocator :: Virtual#(.abstract: Deallocator) = to_virtual#(.abstract: Deallocator)(.value = self)
    allocation = establish_allocation(.storage = storage, .size = size, .deallocator = deallocator)
}

deallocate(.self: $&CountingAllocator, .data: $&UInt8, .size: UIntNative) -> () := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = data)
    free(.pointer = cast#(.to: &Any)(.value = raw_addr))
    self& = (
        .alloc_count = self&.alloc_count,
        .dealloc_count = self&.dealloc_count + 1,
    )
}

CountingAllocator implements Allocator
CountingAllocator implements Deallocator

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .alloc_count = 0,
        .dealloc_count = 0,
    )

    literal ::= from_literal(.data = "abc")
    data ::= reinterpret_reference#(.from: Char, .to: UInt8)(.base = literal).reference

    if 1 == 1 {
        borrowed_view : StringView = (
            .data = data,
            .length = 3,
        )
        borrowed ::= as_c_string(.self = borrowed_view, .allocator = $&allocator)
        if borrowed.storage.size != 4 {
            status_code = 1
            return
        }
        if allocator.alloc_count != 1 {
            status_code = 2
            return
        }
    }

    if allocator.dealloc_count != 1 {
        status_code = 3
        return
    }

    if 1 == 1 {
        copied_view : StringView = (
            .data = data,
            .length = 2,
        )
        copied ::= as_c_string(.self = copied_view, .allocator = $&allocator)
        if copied.storage.size != 3 {
            status_code = 4
            return
        }
        if allocator.alloc_count != 2 {
            status_code = 5
            return
        }
    }

    if allocator.dealloc_count != 2 {
        status_code = 6
        return
    }

    status_code = 0
}
