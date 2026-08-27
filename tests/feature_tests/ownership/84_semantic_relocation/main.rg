Holder : Type = (.allocation: Allocation)

main(.system: System = System()) -> (.status_code: Int32) := {
    result ::= allocate(.self = system.allocator, .size = 1)
    match result {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            source :: Holder = (.allocation = ~payload)
            old_storage_alias ::= &source.allocation
            destination :: Holder
            relocate(.source = $&source, .destination = $&destination)
            if destination.allocation.size != 1 {
                status_code = 2
                return
            }
            deinit(.self = $&destination.allocation)
            status_code = 0
            old_storage_alias
        }
    }
}
