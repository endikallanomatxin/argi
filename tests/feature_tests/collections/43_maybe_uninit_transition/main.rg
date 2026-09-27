main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = size_of(.type = Int32))
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            storage ::= ~payload
            slot ::= trusted_uninit_slot#(.t: Int32)(.allocation = &storage, .index = 0)
            trusted_uninit_write#(.t: Int32)(.allocation = $&storage, .slot = slot, .value = 42)
            value ::= trusted_uninit_take#(.t: Int32)(.allocation = $&storage, .slot = slot)
            trusted_uninit_write#(.t: Int32)(.allocation = $&storage, .slot = slot, .value = 7)
            second ::= trusted_uninit_take#(.t: Int32)(.allocation = $&storage, .slot = slot)
            deinit(.self = $&storage)
            if value == 42 and second == 7 { status_code = 0 } else { status_code = 2 }
        }
    }
}
