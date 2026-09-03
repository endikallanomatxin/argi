main(.system: System = System()) -> (.status_code: Int32) := {
    source_result ::= allocate(.self = system.allocator, .size = 1)
    destination_result ::= allocate(.self = system.allocator, .size = 1)
    match source_result {
        ..error _ { status_code = 1 }
        ..ok ~ source_payload {
            match destination_result {
                ..error _ { status_code = 1 }
                ..ok ~ destination_payload {
                    source :: Allocation = ~source_payload
                    destination :: Allocation = ~destination_payload
                    relocate(.source = $&source, .destination = $&destination)
                    status_code = 0
                }
            }
        }
    }
}
