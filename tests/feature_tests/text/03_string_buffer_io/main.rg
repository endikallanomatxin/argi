main := (.system: System) -> (.status_code: Int32) {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    buffer ::= unwrap_or_abort(
        .value = string_with_capacity(.allocator = $&allocator_storage, .capacity = 8)
    )

    match push_ascii(.self = $&buffer, .byte = 79) {
        ..ok _ {
        }
        ..error _ {
            status_code = 10
            return
        }
    }

    match push_ascii(.self = $&buffer, .byte = 75) {
        ..ok _ {
        }
        ..error _ {
            status_code = 11
            return
        }
    }

    if byte_length(&buffer).count != 2 {
        status_code = 1
        return
    }

    first ::= unwrap_or_abort(.value = bytes_get(.view = &buffer, .index = 0))
    if first != 79 {
        status_code = 2
        return
    }

    second ::= unwrap_or_abort(.value = bytes_get(.view = &buffer, .index = 1))
    if second != 75 {
        status_code = 3
        return
    }

    deinit(.self = $&buffer)
    status_code = 0
}
