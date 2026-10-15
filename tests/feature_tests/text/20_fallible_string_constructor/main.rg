main(.system: System) -> (.status_code: Int32 = 0) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage
    constructed ::= String(.allocator = $&allocator_storage, .length = 3)
    match constructed {
        ..error _ { status_code = 1 }
        ..ok ~value {
            string ::= ~value
            if string.length != 3 { status_code = 2 }
            deinit(.self = $&string)
        }
    }
}
