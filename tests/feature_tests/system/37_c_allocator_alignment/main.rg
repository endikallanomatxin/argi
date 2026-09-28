main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    allocated ::= allocate(.self = $&allocator, .size = 1, .alignment = 64)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            aligned ::= allocation.data.address % 64 == 0
            layout_preserved ::= allocation.size == 1 and allocation.alignment == 64
            deinit(.self = $&allocation)
            if aligned and layout_preserved {
                status_code = 0
            } else {
                status_code = 2
            }
        }
    }
}
