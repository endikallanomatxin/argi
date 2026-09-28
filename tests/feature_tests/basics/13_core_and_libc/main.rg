unsafe_allocation := #import("../../_support/unsafe_allocation")
main () -> (.status_code: Int32) := {
    puts(.string="Hello world!")

    size :: UIntNative = 14
    allocator_storage :: CAllocator = CAllocator()
    assume allocator ::= $&allocator_storage
    allocated ::= allocate(.self = $&allocator_storage, .size = size)
    match allocated {
        ..error _ {
            status_code = 1
            return
        }
        ..ok ~ payload {
            allocation ::= ~payload
            p ::= mutable_reinterpret_reference#(.from: UInt8, .to: Char)(.base = unsafe_allocation.trusted_allocation_byte_rw(.allocation = $&allocation, .offset = 0).reference).reference
            p& = '0'
            puts(.string = p)
            deinit(.self = $&allocation)
        }
    }

    putchar(.character=10)
    status_code = 0
}
