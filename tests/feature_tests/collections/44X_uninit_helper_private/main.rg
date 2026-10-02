main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    allocated ::= allocate(.self = $&allocator_storage, .size = size_of(.type = Int32))
    match allocated {
        ..error _ { status_code = 1 }
        ..ok ~ payload {
            storage ::= ~payload
            slot ::= _trusted_uninit_slot#(.t: Int32)(.allocation = &storage, .index = 0)
            deinit(.self = $&storage)
            status_code = 0
        }
    }
}
