main(.system: System = System()) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            source ::= ~payload
            first :: Allocation
            second :: Allocation
            relocate(.source = $&source, .destination = $&first)
            relocate(.source = $&source, .destination = $&second)
            status_code = 0
        }
    }
}
