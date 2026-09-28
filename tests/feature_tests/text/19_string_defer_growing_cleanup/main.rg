helper(.allocator: $&Allocator) -> (.ok: Bool) := {
    assume allocator

    text ::= String(.allocator = allocator, .capacity = 1)
    #defer deinit(.self = $&text, .allocator = allocator)

    match push_byte(.self = $&text, .byte = 65, .allocator = allocator) {
        ..ok _ {
        }
        ..error _ {
            ok = false
            return
        }
    }

    if text.length != 1 {
        ok = false
        return
    }

    ok = true
}

main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    if helper(.allocator = $&allocator_storage).ok {
        status_code = 0
    } else {
        status_code = 1
    }
}
