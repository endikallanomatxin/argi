main () -> (.status_code: Int32) := {
    puts(.string="Hello world!")

    size :: UIntNative = 14
    allocator :: CAllocator = CAllocator()
    allocated ::= allocate(.self = $&allocator, .size = size)
    match allocated {
        ..error _ {
            status_code = 1
            return
        }
        ..ok ~ payload {
            allocation ::= ~payload
            p ::= mutable_reinterpret_reference#(.from: UInt8, .to: Char)(.base = allocation.data).reference
            p& = '0'
            puts(.string = p)
            deinit(.self = $&allocation)
        }
    }

    putchar(.character=10)
    status_code = 0
}
