read_value(.value: Int32) -> (.result: Int32) := {
    result = value
}

main(.system: System) -> (.status_code: Int32) := {
    allocated ::= allocate(.self = system.allocator, .size = size_of(.type = Int32))
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            storage ::= ~payload
            slot ::= trusted_uninit_slot#(.t: Int32)(.allocation = &storage, .index = 0)
            value ::= read_value(.value = slot)
            deinit(.self = $&storage)
            status_code = value
        }
    }
}
