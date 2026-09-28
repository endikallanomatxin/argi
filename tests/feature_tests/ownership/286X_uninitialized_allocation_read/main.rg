main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = 1)
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            allocation ::= ~payload
            pointer ::= cast#(.to: &UInt8)(.value = allocation.data.address)
            byte ::= pointer&
            deinit(.self = $&allocation)
            if byte == 0 {
                status_code = 0
            } else {
                status_code = 1
            }
        }
    }
}
