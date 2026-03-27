CountingAllocator : Type = (
    .alloc_count: Int32 = 0
    .dealloc_count: Int32 = 0
)

allocate(.self: $&CountingAllocator, .size: UIntNative) -> (.data: $&UInt8) := {
    raw_addr :: UIntNative = cast#(.to: UIntNative)(.value = malloc(.size = size))
    self& = (
        .alloc_count = self&.alloc_count + 1,
        .dealloc_count = self&.dealloc_count,
    )
    data = cast#(.to: $&UInt8)(.value = raw_addr)
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

main() -> (.status_code: Int32) := {
    allocator :: CountingAllocator = (
        .alloc_count = 0,
        .dealloc_count = 0,
    )

    literal ::= from_literal(.data = "abc")
    base_ptr ::= pointer(.self = &literal)
    base_addr :: UIntNative = cast#(.to: UIntNative)(.value = base_ptr)

    if 1 == 1 {
        borrowed_view : StringView = (
            .data = base_addr,
            .length = 3,
        )
        borrowed ::= as_c_string(.self = borrowed_view, .allocator = $&allocator)
        if borrowed.storage.size != 0 {
            status_code = 1
            return
        }
        if allocator.alloc_count != 0 {
            status_code = 2
            return
        }
    }

    if allocator.dealloc_count != 0 {
        status_code = 3
        return
    }

    if 1 == 1 {
        copied_view : StringView = (
            .data = base_addr,
            .length = 2,
        )
        copied ::= as_c_string(.self = copied_view, .allocator = $&allocator)
        if copied.storage.size != 3 {
            status_code = 4
            return
        }
        if allocator.alloc_count != 1 {
            status_code = 5
            return
        }
    }

    if allocator.dealloc_count != 1 {
        status_code = 6
        return
    }

    status_code = 0
}
