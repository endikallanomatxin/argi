main(.system: System = System()) -> (.status_code: Int32) := {
    full :: Path = Path(
        .allocator = system.allocator,
        .view = c_string_as_view(.text = "/tmp/demo/file.txt"),
    )

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

    base :: Path = Path(
        .allocator = system.allocator,
        .view = c_string_as_view(.text = "/tmp/demo"),
    )
    child :: Path = Path(
        .allocator = system.allocator,
        .view = c_string_as_view(.text = "child.txt"),
    )

    joined_result ::= join(.left = &base, .right = &child, .allocator = system.allocator)
    match joined_result {
        ..ok & payload {
            joined ::= copy(.self = payload&.value, .allocator = system.allocator)
            joined_view ::= as_view(.self = &joined)
            if joined_view == "/tmp/demo/child.txt" {
            } else {
                status_code = 8
                return
            }
            deinit(.self = $&joined, .allocator = system.allocator)
        }
        ..error _ {
            status_code = 9
            return
        }
    }

    deinit(.self = $&child, .allocator = system.allocator)
    deinit(.self = $&base, .allocator = system.allocator)
    deinit(.self = $&full, .allocator = system.allocator)
    status_code = 0
}
