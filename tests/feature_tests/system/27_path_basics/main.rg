main(.system: System) -> (.status_code: Int32) := {
    allocator_storage ::= GeneralPurposeAllocator(.allocator = system.page_allocator)
    assume allocator ::= $&allocator_storage

    full :: Path = unwrap_or_abort(.value = Path(
        .allocator = $&allocator_storage,
        .view = c_string_as_view(.text = "/tmp/demo/file.txt"),
    ))

    if is_absolute(.self = &full).ok {
    } else {
        status_code = 1
        return
    }

    name ::= file_name(.self = &full).value
    if name? {
        if name == "file.txt" {
        } else {
            status_code = 2
            return
        }
    } else {
        status_code = 3
        return
    }

    parent_view ::= parent(.self = &full).value
    if parent_view? {
        if parent_view == "/tmp/demo" {
        } else {
            status_code = 4
            return
        }
    } else {
        status_code = 5
        return
    }

    ext ::= extension(.self = &full).value
    match ext {
        ..some payload {
            actual_ext ::= payload.value
            if actual_ext == ".txt" {
            } else {
                status_code = 6
                return
            }
        }
        ..none {
            status_code = 7
            return
        }
    }

    base :: Path = unwrap_or_abort(.value = Path(
        .allocator = $&allocator_storage,
        .view = c_string_as_view(.text = "/tmp/demo"),
    ))
    child :: Path = unwrap_or_abort(.value = Path(
        .allocator = $&allocator_storage,
        .view = c_string_as_view(.text = "child.txt"),
    ))

    joined_result ::= join(.left = &base, .right = &child, .allocator = $&allocator_storage)
    match joined_result {
        ..ok ~ payload {
            joined ::= ~payload
            joined_view ::= as_view(.self = &joined)
            if joined_view == "/tmp/demo/child.txt" {
            } else {
                status_code = 8
                return
            }
            deinit(.self = $&joined, .allocator = $&allocator_storage)
        }
        ..error _ {
            status_code = 9
            return
        }
    }

    deinit(.self = $&child, .allocator = $&allocator_storage)
    deinit(.self = $&base, .allocator = $&allocator_storage)
    deinit(.self = $&full, .allocator = $&allocator_storage)
    status_code = 0
}
