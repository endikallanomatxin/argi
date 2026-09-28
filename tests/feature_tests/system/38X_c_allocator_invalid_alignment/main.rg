main() -> (.status_code: Int32) := {
    allocator :: CAllocator = CAllocator()
    allocated ::= allocate(.self = $&allocator, .size = 8, .alignment = 3)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            deinit(.self = $&allocation)
            status_code = 0
        }
    }
}
