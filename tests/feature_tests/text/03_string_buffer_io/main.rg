main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= String(.allocator = $&allocator_storage, .capacity = 8)

    match push_byte(.self = $&buffer, .byte = 79) {
        ..ok _ {
        }
        ..error _ {
            status_code = 10
            return
        }
    }

    match push_byte(.self = $&buffer, .byte = 75) {
        ..ok _ {
        }
        ..error _ {
            status_code = 11
            return
        }
    }

    if buffer.length != 2 {
        status_code = 1
        return
    }

    first ::= bytes_get(.string = &buffer, .index = 0).byte
    if first != 79 {
        status_code = 2
        return
    }

    second ::= bytes_get(.string = &buffer, .index = 1).byte
    if second != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&buffer, .allocator = $&allocator_storage)
    status_code = 0
}
